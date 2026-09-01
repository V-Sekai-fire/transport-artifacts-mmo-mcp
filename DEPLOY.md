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

## The app's own bao identity

`artifacts-mmo-mcp` has a client certificate of its own — CN
`artifacts-mmo-mcp.internal`, issued from `pki/issue/service` — and a token
carrying only the `artifacts-mmo-mcp` policy:

    path "secret/data/artifacts-mmo/*"     read
    path "secret/metadata/artifacts-mmo/*" read, list
    path "pki/issue/service"               create, update
    path "auth/token/renew-self"           update
    path "sys/health"                      read

**Negative controls, all three verified against the live listener**: a write to
its own secret returns 403, a read of `secret/data/fdb/root` returns 403, and an
issue under `pki/issue/fdb-server` returns 403.

`ArtifactsMMOMCP.Renew` checks hourly: it renews the token daily and re-issues
the certificate once fewer than ten days remain. `pki/roles/service` caps a
certificate at 30 days, so ten days of margin is 240 chances to succeed.

**What renewal cannot fix.** Reaching bao needs a valid certificate, so a
machine that was down past the expiry cannot re-issue its way back. That case
falls back to the Fly secrets, which still carry the game token, and
`GET /health` reports `bao.configured: false`. Re-issue by hand:

```sh
flyctl ssh console -a spot-broker -C "sh -c \"curl -s --cert /app/bao-tls/client-cert.pem \
  --key /app/bao-tls/client-key.pem --cacert /app/bao-tls/ca-chain.pem \
  -H 'X-Vault-Token: <root>' -X POST -d '{\\\"common_name\\\":\\\"artifacts-mmo-mcp.internal\\\",\\\"ttl\\\":\\\"720h\\\"}' \
  https://weftspun-bao.internal:8200/v1/pki/issue/service\""
```

Then set `BAO_CLIENT_CERT_B64` and `BAO_CLIENT_KEY_B64` from the result.

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
- `/health` reports `bao.configured: true` with `cert_days_left` above ten. A
  falling number that never resets means renewal is not running.

## Filling in the word-labels with generated art

The world page renders a scribble sprite when Kenney has one and a word label
when it does not. That's the honest fallback. The optional next step is
generating a scribble-style sprite per missing code with Wan 2.1, and dropping
it into `priv/static/wan/`; the page picks it up on the next load with no
code change.

```sh
# what still needs art (no GPU needed)
python scripts/gen_wan_sprites.py --world /path/to/world.json --list-missing

# generate one thing to see the prompt work
python scripts/gen_wan_sprites.py --world /path/to/world.json \
  --codes monster:goblin

# generate everything (GPU, ~2-3 min per image at 1024px on 8 GB)
python scripts/gen_wan_sprites.py --world /path/to/world.json
```

The Wan checkpoint dir and any offload flags belong in the caller's env, not
in this script. Local CUDA box, or rent a RunPod per CLAUDE.md's `runpod-batch-gpu`
recipe.
