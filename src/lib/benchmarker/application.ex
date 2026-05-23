defmodule Benchmarker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    role = role()

    children =
      case role do
        :worker ->
          # Worker nodes run Oban only — no HTTP endpoint, no PubSub, no Finch.
          [
            Benchmarker.Repo,
            {Oban, Application.fetch_env!(:benchmarker, Oban)}
          ]

        :web ->
          # Web nodes serve HTTP and insert Oban jobs but never process them
          # (queues: [] is set in runtime.exs for this role).
          [
            BenchmarkerWeb.Telemetry,
            Benchmarker.Repo,
            {DNSCluster, query: Application.get_env(:benchmarker, :dns_cluster_query) || :ignore},
            {Phoenix.PubSub, name: Benchmarker.PubSub},
            {Finch, name: Benchmarker.Finch},
            {Oban, Application.fetch_env!(:benchmarker, Oban)},
            BenchmarkerWeb.Endpoint
          ]
      end

    opts = [strategy: :one_for_one, name: Benchmarker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Pod role. `:web` serves HTTP and enqueues jobs; `:worker` processes them.
  # Set BENCHMARKER_ROLE=worker on dedicated benchmark hosts.
  defp role do
    case System.get_env("BENCHMARKER_ROLE") do
      "worker" -> :worker
      _ -> :web
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    BenchmarkerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
