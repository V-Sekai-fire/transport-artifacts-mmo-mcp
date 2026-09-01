<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# artifacts-mmo-mcp

MCP server that plays ArtifactsMMO, records paired planner/API traces for
[taskweft](https://github.com/taskweft/taskweft), and serves a spectator page
showing what every character is doing right now.

```sh
mix deps.get
ARTIFACTS_MMO_TOKEN=... ARTIFACTS_MMO_CHARACTER=... MCP_OPEN=1 mix run --no-halt
```

- `http://localhost:5243/` — spectator page, no credential.
- `http://localhost:5243/api/characters` — the state it polls.
- `http://localhost:5243/mcp` — MCP endpoint, bearer-gated (see below).

## Tools

`start_run` and `record_plan` write the planner layer. `character`, `map_at`,
`catalog` and `bank_items` read. `move`, `fight`, `gather`, `rest`, `craft`,
`recycle`, `use_item`, `equip`, `unequip`, `bank_deposit`, `bank_withdraw`,
`task_new`, `task_complete`, `npc_buy` and `npc_sell` act.

Every acting tool takes `run_id` and `step`. Those two fields are the join
between the plan that chose an action and the request that carried it out; a
call without them plays the game and writes no trace.

## Traces

Two layers under `TRACE_DIR` (default `traces/`), never interleaved:

    traces/planner/<run_id>.jsonl   what taskweft was asked, what it returned
    traces/api/<run_id>.jsonl       every game request and response

They are separate because they are two corpora with two lifetimes. A planner
entry whose `step` matches no API entry is a plan that was never executed —
countable when the layers are apart, lost in a merge.

`scripts/pack_traces.py` converts a finished run to zstd parquet for the
archive, verifying row count and a SHA-256 over the canonical JSON of every row
before it reports success. It never deletes a source.

```sh
python scripts/pack_traces.py traces/ --out packed/
python scripts/pack_traces.py --self-test
```

## Why `/mcp` is gated and `/` is not

The spectator page shows positions, levels, cooldowns and the last action each
character was asked to take. None of that is a credential and the account token
never reaches a response body, so the page needs no login.

`/mcp` can move characters, spend gold and empty a bank. On a public hostname
an open `/mcp` hands the account to whoever finds it, so it requires
`MCP_AUTH_TOKEN` as a bearer and answers 503 when that variable is unset.
`MCP_OPEN=1` is the explicit opt-out for a local run — the default is closed,
because a gate that defaults to open is not a gate.

## Environment

| variable | default | what it is |
| --- | --- | --- |
| `PORT` | `5243` | listen port |
| `ARTIFACTS_MMO_API_URL` | `https://api.artifactsmmo.com` | game API |
| `ARTIFACTS_MMO_TOKEN` | unset | account token, from OpenBao `secret/artifacts-mmo/api` |
| `ARTIFACTS_MMO_CHARACTER` | unset | character used when a tool call omits one |
| `MCP_AUTH_TOKEN` | unset | bearer required on `/mcp` |
| `MCP_OPEN` | unset | `1` serves `/mcp` with no bearer, local runs only |
| `TRACE_DIR` | `traces` | where the two layers are written |

Built against the game's OpenAPI 8.2.2 spec (`https://api.artifactsmmo.com/openapi.json`).
