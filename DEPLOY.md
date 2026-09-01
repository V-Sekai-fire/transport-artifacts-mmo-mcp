<!-- SPDX-License-Identifier: MIT -->
<!-- Copyright (c) 2026 K. S. Ernest (iFire) Lee -->

# Deploy

Fly.io app `artifacts-mmo-mcp` in `sjc`, spectator page on a `chibifire.com`
hostname. Same shape as `spot-broker`, which already serves
`account.chibifire.com` this way.

## Secrets

The account token comes out of OpenBao, not out of a shell history.

```sh
bao kv put secret/artifacts-mmo/api token=<game token> character=<name>
flyctl secrets set -a artifacts-mmo-mcp \
  ARTIFACTS_MMO_TOKEN="$(bao kv get -field=token secret/artifacts-mmo/api)" \
  ARTIFACTS_MMO_CHARACTER="$(bao kv get -field=character secret/artifacts-mmo/api)" \
  MCP_AUTH_TOKEN="$(openssl rand -hex 32)"
```

`MCP_AUTH_TOKEN` must be set before the first deploy. Without it `/mcp`
answers 503, which is the intended state for a public hostname — but a
deploy that forgets it is a server that cannot plan, so set it first and
put the value in bao beside the game token.

## Volume and app

```sh
flyctl apps create artifacts-mmo-mcp
flyctl volumes create traces -a artifacts-mmo-mcp -r sjc -s 1
flyctl deploy
```

The volume holds `/data/traces`. `auto_stop_machines` is off: a machine that
suspends stops polling, and a gap in the trace is indistinguishable from a
character that did nothing.

## Hostname

```sh
flyctl certs add watch.chibifire.com -a artifacts-mmo-mcp
flyctl ips list -a artifacts-mmo-mcp
```

DNS is Cloudflare. Add the records `flyctl certs show watch.chibifire.com`
asks for — an A to the app's v4 IP and an AAAA to its v6 — then re-check:

```sh
flyctl certs check watch.chibifire.com -a artifacts-mmo-mcp
```

## Verification

- `curl -s https://watch.chibifire.com/health` returns `"token_present": true`.
- `curl -s https://watch.chibifire.com/api/characters` lists characters with no
  credential and carries no token in the body.
- `curl -s -o /dev/null -w '%{http_code}' -X POST https://watch.chibifire.com/mcp`
  returns 401. **This is the negative control**: a 200 here means the account is
  open to the internet, and the deploy is wrong.
