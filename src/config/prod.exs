import Config

config :logger, level: :info
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: Benchmarker.Finch
config :swoosh, local: false
