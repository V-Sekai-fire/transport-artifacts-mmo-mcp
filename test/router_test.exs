# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.RouterTest do
  use ExUnit.Case, async: false
  use Plug.Test

  alias ArtifactsMMOMCP.Router

  setup do
    System.delete_env("MCP_AUTH_TOKEN")
    System.delete_env("MCP_OPEN")
    :ok
  end

  defp call(conn), do: Router.call(conn, Router.init([]))

  test "health reports whether a game token is present" do
    conn = call(conn(:get, "/health"))
    assert conn.status == 200
    assert %{"status" => "ok", "token_present" => _} = Jason.decode!(conn.resp_body)
  end

  test "spectator state is served without a credential" do
    conn = call(conn(:get, "/api/characters"))
    assert conn.status == 200
    assert %{"characters" => _} = Jason.decode!(conn.resp_body)
  end

  test "mcp is closed when no token is configured" do
    conn = call(conn(:post, "/mcp", ""))
    assert conn.status == 503
  end

  test "mcp opens locally only on an explicit opt-out" do
    System.put_env("MCP_OPEN", "1")
    conn = call(conn(:post, "/mcp", ""))
    refute conn.status == 503
  end

  test "mcp rejects a wrong bearer and accepts the configured one" do
    System.put_env("MCP_AUTH_TOKEN", "sekret")

    wrong =
      conn(:post, "/mcp", "")
      |> put_req_header("authorization", "Bearer nope")
      |> call()

    assert wrong.status == 401

    right =
      conn(:post, "/mcp", "")
      |> put_req_header("authorization", "Bearer sekret")
      |> call()

    refute right.status in [401, 503]
  end
end
