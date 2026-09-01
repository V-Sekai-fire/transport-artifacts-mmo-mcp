# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Trace do
  @moduledoc """
  Two trace layers for one run, written as newline-delimited JSON under
  `TRACE_DIR` (default `traces/`):

    * `traces/planner/<run_id>.jsonl` — what the planner was asked and what it
      returned. This is the layer that trains against taskweft.
    * `traces/api/<run_id>.jsonl` — every game request and response. This is
      the layer that makes a run replayable.

  They are kept apart rather than interleaved because they are two corpora with
  two lifetimes, and joined on `(run_id, step)` when a reader wants both. A
  planner entry whose `step` matches no API entry is a plan that was never
  executed, which is a fact worth being able to count rather than one to lose
  in a merge.

  `mix artifacts_mmo.pack_traces` converts a finished run to zstd parquet for
  the archive; JSONL is the write format only.
  """

  use GenServer
  require Logger

  @name __MODULE__

  def start_link(opts), do: GenServer.start_link(@name, opts, name: @name)

  @doc "Directory holding both layers."
  def dir, do: System.get_env("TRACE_DIR", "traces")

  @doc """
  Open a run. `metadata` records what produced it — planner endpoint, domain,
  character, game API version — so a corpus entry answers where it came from
  without a second lookup.
  """
  def start_run(metadata \\ %{}) do
    run_id = random_id()
    GenServer.call(@name, {:start_run, run_id, metadata})
    run_id
  end

  @doc "Record one planner call: the todo_list given, the plan returned."
  def plan_step(entry), do: GenServer.cast(@name, {:write, :planner, entry})

  @doc "Record one game API call. Called by `ArtifactsMMOMCP.Client`."
  def api_call(entry), do: GenServer.cast(@name, {:write, :api, entry})

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def handle_call({:start_run, run_id, metadata}, _from, state) do
    entry = %{run_id: run_id, step: 0, kind: "run_start", metadata: metadata}
    for layer <- [:planner, :api], do: append(layer, entry)
    {:reply, run_id, state}
  end

  @impl true
  def handle_cast({:write, layer, entry}, state) do
    append(layer, entry)
    {:noreply, state}
  end

  defp append(_layer, %{run_id: nil}), do: :ok

  defp append(layer, entry) do
    entry = Map.put_new(entry, :ts, DateTime.utc_now() |> DateTime.to_iso8601())
    layer_dir = Path.join(dir(), to_string(layer))
    File.mkdir_p!(layer_dir)
    path = Path.join(layer_dir, "#{entry.run_id}.jsonl")

    case Jason.encode(entry) do
      {:ok, line} ->
        File.write!(path, line <> "\n", [:append])

      {:error, reason} ->
        Logger.warning("trace entry not encodable, dropped: #{inspect(reason)}")
    end
  end

  defp random_id, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
end
