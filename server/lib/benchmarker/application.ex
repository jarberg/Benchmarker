defmodule Benchmarker.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    role = role()

    base = [
      BenchmarkerWeb.Telemetry,
      Benchmarker.Repo,
      {DNSCluster, query: Application.get_env(:benchmarker, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Benchmarker.PubSub},
      {Finch, name: Benchmarker.Finch},
      {Oban, Application.fetch_env!(:benchmarker, Oban)}
    ]

    children =
      case role do
        :worker -> base
        _ -> base ++ [BenchmarkerWeb.Endpoint]
      end

    opts = [strategy: :one_for_one, name: Benchmarker.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Pod role. `:web` runs the Phoenix endpoint + Oban; `:worker` runs Oban only.
  # Set `BENCHMARKER_ROLE=worker` on dedicated benchmark hosts.
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
