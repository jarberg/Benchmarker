# syntax=docker/dockerfile:1.6
# Multi-stage Phoenix release image for the Benchmarker server.

ARG ELIXIR_VERSION=1.16.3
ARG OTP_VERSION=26.2.5
ARG DEBIAN_VERSION=bookworm-20240612-slim
ARG NODE_VERSION=20

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

# ── Stage 1: build assets ───────────────────────────────────────────────────
FROM node:${NODE_VERSION}-bookworm-slim AS assets
WORKDIR /app/assets
COPY assets/package*.json ./
RUN npm ci
COPY assets/ ./
RUN npm run build

# ── Stage 2: build Elixir release ───────────────────────────────────────────
FROM ${BUILDER_IMAGE} AS builder
RUN apt-get update -y && apt-get install -y build-essential git \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV="prod"
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib

# bring in the assets built in stage 1
COPY --from=assets /app/priv/static/assets priv/static/assets

COPY config/runtime.exs config/
COPY rel rel
RUN chmod +x rel/overlays/bin/server
RUN mix compile
RUN mix phx.digest
RUN mix release

# ── Stage 3: runtime ────────────────────────────────────────────────────────
FROM ${RUNNER_IMAGE} AS runner
RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses5 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app
RUN useradd --create-home --shell /bin/bash app \
    && chown app:app /app \
    && mkdir -p /var/lib/benchmarker/uploads \
    && chown app:app /var/lib/benchmarker/uploads
USER app

COPY --from=builder --chown=app:app /app/_build/prod/rel/benchmarker ./

ENV PHX_SERVER=true
ENV PORT=4000
EXPOSE 4000

CMD ["/app/bin/server"]
