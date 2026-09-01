# SPDX-License-Identifier: MIT
# Copyright (c) 2026 K. S. Ernest (iFire) Lee

defmodule ArtifactsMMOMCP.Application do
  @moduledoc """
  OTP application: the trace writer, then a Cowboy endpoint serving the MCP
  server over HTTP.

  Runtime env:

    * `PORT` — listen port, default `5243`.
    * `ARTIFACTS_MMO_API_URL` — game API, default `https://api.artifactsmmo.com`.
    * `ARTIFACTS_MMO_TOKEN` — account token; `ArtifactsMMOMCP.Bao` overwrites it
      at boot when bao is reachable, so bao is the record and this is a fallback.
    * `ARTIFACTS_MMO_CHARACTER` — character used when a tool call omits one.
    * `TRACE_DIR` — where the two trace layers are written, default `traces`.

  The spectator page at `/` needs no credential of its own.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    ArtifactsMMOMCP.Bao.load()
    port = String.to_integer(System.get_env("PORT", "5243"))

    if ArtifactsMMOMCP.Client.token() == "" do
      Logger.warning("ARTIFACTS_MMO_TOKEN unset: reads will work, actions will be refused 401")
    end

    Logger.info("artifacts-mmo-mcp on 0.0.0.0:#{port}, traces in #{ArtifactsMMOMCP.Trace.dir()}")

    children = [
      {ArtifactsMMOMCP.Trace, []},
      {ArtifactsMMOMCP.Renew, []},
      {ArtifactsMMOMCP.Watch, []},
      {ArtifactsMMOMCP.World, []},
      {Plug.Cowboy,
       scheme: :http, plug: ArtifactsMMOMCP.Router, options: [port: port, ip: {0, 0, 0, 0}]}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: ArtifactsMMOMCP.Supervisor)
  end
end
