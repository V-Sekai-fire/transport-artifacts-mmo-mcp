# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.TraceTest do
  use ExUnit.Case, async: false

  alias ArtifactsMMOMCP.Trace

  setup do
    dir = Path.join(System.tmp_dir!(), "trace-#{System.unique_integer([:positive])}")
    System.put_env("TRACE_DIR", dir)
    File.mkdir_p!(Path.join(dir, "api"))
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  defp read(dir, layer, run_id) do
    Path.join([dir, layer, "#{run_id}.jsonl"])
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(&Jason.decode!/1)
  end

  test "the two layers join on run_id and step", %{dir: dir} do
    run_id = Trace.start_run(%{"character" => "test"})
    Trace.plan_step(%{run_id: run_id, step: 1, plan: [%{"task" => ["move", 1, 2]}]})
    Trace.api_call(%{run_id: run_id, step: 1, method: :post, path: "/x", status: 200})
    Process.sleep(50)

    [_start, plan] = read(dir, "planner", run_id)
    [_start, api] = read(dir, "api", run_id)

    assert plan["step"] == api["step"]
    assert plan["run_id"] == api["run_id"]
    assert api["status"] == 200
  end

  test "an untraced call writes nothing rather than a file with no run", %{dir: dir} do
    Trace.api_call(%{run_id: nil, step: nil, path: "/x", status: 200})
    Process.sleep(50)
    assert File.ls!(Path.join(dir, "api")) == []
  end
end
