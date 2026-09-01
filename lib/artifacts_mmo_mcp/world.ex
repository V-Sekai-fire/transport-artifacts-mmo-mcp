# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.World do
  @moduledoc """
  The whole game world, cached in memory: every tile from `GET /maps`, joined
  to the live character list `ArtifactsMMOMCP.Watch` polls.

  Tiles do not change during play — a workshop stays a workshop — so the map
  is fetched once at boot and refreshed hourly. What moves is the characters,
  and they come from `Watch` at the frame the client asks for the world.
  """

  use GenServer
  require Logger

  alias ArtifactsMMOMCP.{Client, Watch}

  @name __MODULE__
  @refresh_ms :timer.hours(1)
  @page_size 100

  def start_link(opts), do: GenServer.start_link(@name, opts, name: @name)

  @doc "The whole world plus the current character snapshot."
  def snapshot do
    case GenServer.whereis(@name) do
      nil ->
        %{tiles: [], bounds: %{}, fetched_at: nil, error: "world not running", characters: []}

      pid ->
        base = GenServer.call(pid, :snapshot)
        Map.put(base, :characters, Watch.snapshot().characters)
    end
  end

  @impl true
  def init(_opts) do
    send(self(), :refresh)
    {:ok, %{tiles: [], bounds: %{}, fetched_at: nil, error: "not fetched yet"}}
  end

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  @impl true
  def handle_info(:refresh, state) do
    Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, fetch(state)}
  end

  defp fetch(state) do
    case fetch_all(1, []) do
      {:ok, raw} ->
        tiles = Enum.map(raw, &project/1)
        Logger.info("world: cached #{length(tiles)} tiles across #{layers(tiles)} layers")
        %{state | tiles: tiles, bounds: bounds(tiles), fetched_at: iso_now(), error: nil}

      {:error, reason} ->
        Logger.warning("world: refresh failed: #{reason}")
        %{state | error: reason, fetched_at: iso_now()}
    end
  end

  defp fetch_all(page, acc) do
    case Client.get("/maps", size: @page_size, page: page) do
      {:ok, %{"data" => data, "pages" => pages}} ->
        acc = acc ++ data
        if page >= pages, do: {:ok, acc}, else: fetch_all(page + 1, acc)

      {:error, reason} ->
        {:error, Client.describe_error(reason)}
    end
  end

  # Everything a spectator page needs; nothing that would drift when the game
  # ships a new field.
  defp project(tile) do
    interactions = tile["interactions"] || %{}
    content = interactions["content"]
    transition = interactions["transition"]

    %{
      map_id: tile["map_id"],
      name: tile["name"],
      layer: tile["layer"],
      x: tile["x"],
      y: tile["y"],
      skin: tile["skin"],
      family: family(tile["skin"]),
      content_type: content && content["type"],
      content_code: content && content["code"],
      transition: transition && transition["layer"],
      transition_gated: gated?(transition)
    }
  end

  defp family(nil), do: nil
  defp family(skin), do: skin |> String.replace(~r/_\d+$/, "") |> String.replace(~r/\d+$/, "")

  defp gated?(%{"conditions" => [_ | _]}), do: true
  defp gated?(_), do: false

  defp bounds(tiles) do
    tiles
    |> Enum.group_by(& &1.layer)
    |> Map.new(fn {layer, ts} ->
      xs = Enum.map(ts, & &1.x)
      ys = Enum.map(ts, & &1.y)

      {layer,
       %{min_x: Enum.min(xs), max_x: Enum.max(xs), min_y: Enum.min(ys), max_y: Enum.max(ys)}}
    end)
  end

  defp layers(tiles), do: tiles |> MapSet.new(& &1.layer) |> MapSet.size()
  defp iso_now, do: DateTime.utc_now() |> DateTime.to_iso8601()
end
