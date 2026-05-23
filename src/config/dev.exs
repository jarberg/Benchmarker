import Config

config :benchmarker, Benchmarker.Repo,
  username: System.get_env("POSTGRES_USER", "postgres"),
  password: System.get_env("POSTGRES_PASSWORD", "postgres"),
  hostname: System.get_env("POSTGRES_HOST", "localhost"),
  database: System.get_env("POSTGRES_DB", "benchmarker_dev"),
  port: String.to_integer(System.get_env("POSTGRES_PORT", "5432")),
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :benchmarker, BenchmarkerWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "dev-secret-key-base-please-change-me-it-must-be-at-least-64-bytes-long-aaaaaaaaaaaaaaaaa",
  watchers: [
    npm: ["run", "dev", cd: Path.expand("../assets", __DIR__)]
  ],
  live_reload: [
    patterns: [
      ~r"priv/static/.*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/benchmarker_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
config :phoenix_live_view, debug_heex_annotations: true, enable_expensive_runtime_checks: true

config :swoosh, :api_client, false
