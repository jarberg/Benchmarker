defmodule BenchmarkerWeb.PageController do
  use BenchmarkerWeb, :controller
  alias Benchmarker.Benchmarks

  @doc """
  Renders the single-page Inertia React app and seeds it with the initial
  list of jobs and saved config presets.
  """
  def index(conn, _params) do
    jobs = Benchmarks.list_jobs!() |> Enum.map(&serialize_job/1)
    configs = Benchmarks.list_configs!() |> Enum.map(&serialize_config/1)

    conn
    |> assign_prop(:jobs, jobs)
    |> assign_prop(:configs, configs)
    |> render_inertia("Dashboard")
  end

  defp serialize_job(j) do
    %{
      id: j.id,
      game_name: j.game_name,
      status: to_string(j.status),
      worker_id: j.worker_id,
      config: j.config || %{},
      results: j.results,
      error: j.error,
      created_at: j.created_at,
      updated_at: j.updated_at
    }
  end

  defp serialize_config(c) do
    %{id: c.id, name: c.name, config: c.config || %{}}
  end
end
