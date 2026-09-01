# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Watch do
  @moduledoc """
  Live state for the spectator page: polls `/my/characters` and remembers the
  last action this server issued for each character.

  Two sources because neither is enough alone. The game reports where a
  character is and how long its cooldown has left, but not what the cooldown is
  for; this server knows what it asked for, but not what came of it until the
  next poll. What a character is "currently doing" is the join.

  Polls are not traced. A spectator refreshing a browser tab is not part of a
  run, and a poll landing in the API layer would be a corpus row nothing
  planned.
  """

  use GenServer

  alias ArtifactsMMOMCP.Client

  @name __MODULE__
  @poll_ms 2_000

  def start_link(opts), do: GenServer.start_link(@name, opts, name: @name)

  @doc "Latest character list joined to the last action issued for each."
  def snapshot do
    case GenServer.whereis(@name) do
      nil -> %{characters: [], fetched_at: nil, error: "watcher not running"}
      pid -> GenServer.call(pid, :snapshot)
    end
  end

  @doc "Record what this server just asked a character to do."
  def note_action(character, action, status) do
    case GenServer.whereis(@name) do
      nil -> :ok
      pid -> GenServer.cast(pid, {:action, character, action, status})
    end
  end

  @impl true
  def init(_opts) do
    send(self(), :poll)
    {:ok, %{characters: [], fetched_at: nil, error: nil, actions: %{}}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    characters = Enum.map(state.characters, &decorate(&1, state.actions))
    reply = %{characters: characters, fetched_at: state.fetched_at, error: state.error}
    {:reply, reply, state}
  end

  @impl true
  def handle_cast({:action, character, action, status}, state) do
    entry = %{action: action, status: status, at: DateTime.utc_now() |> DateTime.to_iso8601()}
    {:noreply, put_in(state.actions[character], entry)}
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_ms)
    {:noreply, poll(state)}
  end

  defp poll(state) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    case Client.get("/my/characters") do
      {:ok, %{"data" => characters}} when is_list(characters) ->
        %{state | characters: characters, fetched_at: now, error: nil}

      {:ok, other} ->
        %{state | fetched_at: now, error: "unexpected shape: #{inspect(other)}"}

      {:error, reason} ->
        %{state | fetched_at: now, error: Client.describe_error(reason)}
    end
  end

  @keep ~w(name level xp max_xp gold hp max_hp x y layer map_id cooldown
           cooldown_expiration task task_type task_progress task_total
           inventory_max_items skin)

  defp decorate(character, actions) do
    character
    |> Map.take(@keep)
    |> Map.put("inventory_used", inventory_used(character))
    |> Map.put("last_action", Map.get(actions, character["name"]))
  end

  defp inventory_used(%{"inventory" => slots}) when is_list(slots) do
    Enum.reduce(slots, 0, fn slot, acc -> acc + (slot["quantity"] || 0) end)
  end

  defp inventory_used(_), do: 0
end
