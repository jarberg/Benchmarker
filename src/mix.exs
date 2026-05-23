defmodule Benchmarker.MixProject do
  use Mix.Project

  def project do
    [
      app: :benchmarker,
      version: "0.1.0",
      elixir: "~> 1.16",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: Mix.compilers()
    ]
  end

  def application do
    [
      mod: {Benchmarker.Application, []},
      extra_applications: [:logger, :runtime_tools, :os_mon]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Phoenix core
      {:phoenix, "~> 1.7.14"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.11"},
      {:postgrex, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},

      # NOTE: LiveView removed

      {:floki, ">= 0.30.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.4"},
      {:swoosh, "~> 1.5"},
      {:finch, "~> 0.13"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 0.20"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},

      # Ash framework
      {:ash, "~> 3.4"},
      {:ash_postgres, "~> 2.4"},
      {:ash_phoenix, "~> 2.1"},
      {:ash_json_api, "~> 1.4"},
      {:ash_oban, "~> 0.2"},
      {:oban, "~> 2.18"},

      # Inertia.js bridge (React frontend architecture)
      {:inertia, "~> 2.2"},

      # CSV / workers
      {:nimble_csv, "~> 1.2"},

      # Dev tooling
      {:igniter, "~> 0.4", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      setup: [
        "deps.get",
        "ash.setup",
        "assets.setup",
        "assets.build"
      ],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],

      # Frontend (Inertia + React)
      "assets.setup": ["cmd --cd assets npm install"],
      "assets.build": ["cmd --cd assets npm run build"],
      "assets.deploy": [
        "cmd --cd assets npm run build",
        "phx.digest"
      ]
    ]
  end
end
