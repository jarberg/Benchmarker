import Config

config :benchmarker,
  ecto_repos: [Benchmarker.Repo],
  ash_domains: [Benchmarker.Benchmarks],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Endpoint
config :benchmarker, BenchmarkerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: BenchmarkerWeb.ErrorHTML, json: BenchmarkerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Benchmarker.PubSub,
  live_view: [signing_salt: "vqv9SjzN"]

# Mailer (unused but Phoenix expects it)
config :benchmarker, Benchmarker.Mailer, adapter: Swoosh.Adapters.Local

# JSON
config :phoenix, :json_library, Jason

# AshJsonApi
config :ash_json_api, :authorize?, false

# Inertia.js
config :inertia,
  endpoint: BenchmarkerWeb.Endpoint,
  static_paths: ["/assets/app.js"],
  default_version: "1",
  camelize_props: false,
  history: [encrypt: true],
  ssr: false,
  raise_on_ssr_failure: config_env() != :prod

# Oban (background jobs — replaces RQ for the worker queue once migrated)
# Queues are intentionally not set here — runtime.exs assigns them based on
# BENCHMARKER_ROLE so the web role never processes jobs.
config :benchmarker, Oban,
  engine: Oban.Engines.Basic,
  repo: Benchmarker.Repo

# Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{config_env()}.exs"
