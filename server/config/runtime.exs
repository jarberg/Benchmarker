import Config

if System.get_env("PHX_SERVER") do
  config :benchmarker, BenchmarkerWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      Example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :benchmarker, Benchmarker.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      Generate one with: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :benchmarker, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :benchmarker, BenchmarkerWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base,
    server: true

  config :benchmarker, :upload_dir, System.get_env("UPLOAD_DIR", "/var/lib/benchmarker/uploads")

  # Role-based Oban queue config.
  # - web:    Oban runs with no queues so it can insert jobs but never steals them.
  # - worker: Oban processes the benchmarks queue.
  case System.get_env("BENCHMARKER_ROLE") do
    "worker" ->
      concurrency = String.to_integer(System.get_env("OBAN_CONCURRENCY") || "4")
      config :benchmarker, Oban, queues: [benchmarks: concurrency]

    _ ->
      config :benchmarker, Oban, queues: []
  end
end
