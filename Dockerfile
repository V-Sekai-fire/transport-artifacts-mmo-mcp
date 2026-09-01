FROM elixir:1.18-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

COPY config config
COPY lib lib
COPY priv priv
RUN mix release artifacts_mmo_mcp

FROM debian:trixie-slim AS app
RUN apt-get update && apt-get install -y --no-install-recommends \
        libstdc++6 openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/_build/prod/rel/artifacts_mmo_mcp ./
ENV TRACE_DIR=/data/traces
CMD ["/app/bin/artifacts_mmo_mcp", "start"]
