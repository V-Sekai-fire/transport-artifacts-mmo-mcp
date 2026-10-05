<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# transport-artifacts-mmo-mcp

A Model Context Protocol server that plays an online role-playing game over its HTTP API and records planner and game traces for taskweft.

## What it is for

Its tools read and act on game characters, and every acting call carries a run and step that join the plan that chose an action to the request that carried it out. Planner traces and game traces are written as separate layers, so a planned step that was never executed stays countable, and a script packs a finished run into ZStandard parquet. A spectator page shows each character's state with no credential; the MCP endpoint requires a bearer token unless a local run opts out.

## Build and run

```sh
mix deps.get
mix run --no-halt
```

`.env.example` names the settings it reads. A local run sets `MCP_AUTH_TOKEN` or `MCP_OPEN=1`, or `/mcp` answers 503. `DEPLOY.md` covers the hosted deployment.

## Licence

MIT; see `LICENSE`.
