# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Router do
  @moduledoc """
  HTTP surface: `GET /` for the spectator page, `GET /api/characters` for the
  state it polls, `GET /health` for liveness, `/mcp` for the MCP endpoint.

  Nothing on the spectator path asks for a credential. The account token stays
  in this process and never reaches a response body: the page sees positions,
  levels and cooldowns, which is what makes it worth watching and all it needs.

  `/mcp` is the opposite case and is gated separately. It can move characters,
  spend gold and empty a bank, so on a public hostname an open `/mcp` hands the
  account to anyone who finds it. It requires `MCP_AUTH_TOKEN` as a bearer, and
  when that variable is unset it answers 503 rather than answering at all —
  `MCP_OPEN=1` is the explicit opt-out for a local run.
  """

  use Plug.Router

  plug(Plug.Logger)

  plug(Plug.Static, at: "/static", from: {:artifacts_mmo_mcp, "priv/static"})

  plug(:match)
  plug(:gate_mcp)
  plug(:dispatch)

  @version Mix.Project.config()[:version]

  @mcp_init [
    handler: ArtifactsMMOMCP.Server,
    server_info: %{name: "artifacts-mmo-mcp", version: @version},
    tools: [],
    sse_enabled: true,
    cors_enabled: true,
    allowed_origins: :any,
    validate_origin: false
  ]

  get "/world" do
    conn |> put_resp_header("location", "/") |> send_resp(301, "")
  end

  get "/api/world" do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(ArtifactsMMOMCP.World.snapshot()))
  end

  get "/" do
    conn
    |> put_resp_content_type("text/html")
    |> send_file(200, Application.app_dir(:artifacts_mmo_mcp, "priv/static/world.html"))
  end

  get "/api/characters" do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(ArtifactsMMOMCP.Watch.snapshot()))
  end

  get "/health" do
    body = %{
      "status" => "ok",
      "version" => @version,
      "token_present" => ArtifactsMMOMCP.Client.token() != "",
      "bao" => ArtifactsMMOMCP.Renew.status()
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(body))
  end

  forward("/mcp", to: ExMCP.HttpPlug, init_opts: @mcp_init)

  match _ do
    send_resp(conn, 404, "not found")
  end

  defp gate_mcp(%Plug.Conn{path_info: ["mcp" | _]} = conn, _opts) do
    expected = System.get_env("MCP_AUTH_TOKEN", "")
    open? = System.get_env("MCP_OPEN") == "1"

    cond do
      expected == "" and open? ->
        conn

      expected == "" ->
        halt_json(conn, 503, "MCP_AUTH_TOKEN unset; set it, or MCP_OPEN=1 locally")

      bearer(conn) == expected ->
        conn

      true ->
        halt_json(conn, 401, "bearer token required")
    end
  end

  defp gate_mcp(conn, _opts), do: conn

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> token
      _ -> ""
    end
  end

  defp halt_json(conn, status, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode!(%{"error" => message}))
    |> halt()
  end
end
