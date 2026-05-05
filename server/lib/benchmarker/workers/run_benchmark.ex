defmodule Benchmarker.Workers.RunBenchmark do
  @moduledoc """
  Oban job that runs a benchmark for a single `Job` row.

  Replaces the Python RQ worker (`worker/agent.py` + `worker_task.py`):
    1. Fetch the job via Ash
    2. Mark it `:running`
    3. Dispatch to the right engine runner (generic / unity / unreal)
    4. Write results back via the `submit_results` action
    5. On failure, mark `:failed` with the error message
  """

  use Oban.Worker,
    queue: :benchmarks,
    max_attempts: 1

  alias Benchmarker.Benchmarks
  alias Benchmarker.Workers.Runners

  require Logger

  @impl Oban.Worker
  # Allow long-running benchmarks (default 1h, can override via config).
  def timeout(_job), do: Application.get_env(:benchmarker, :benchmark_timeout_ms, 3_600_000)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}}) do
    worker_id = worker_id()
    Logger.info("[#{worker_id}] starting job #{job_id}")

    with {:ok, job} <- Benchmarks.get_job(job_id),
         {:ok, _} <- Benchmarks.update_job_status(job, %{status: :running, worker_id: worker_id}) do
      try do
        results = Runners.run(job_id, job.file_path, job.config || %{}, job.args || [])
        log = Map.get(results, "log", "")
        clean_results = Map.delete(results, "log")

        {:ok, _} =
          Benchmarks.submit_results(job, %{
            worker_id: worker_id,
            status: :completed,
            results: clean_results,
            log: log,
            error: nil
          })

        Logger.info("[#{worker_id}] job #{job_id} completed")
        :ok
      rescue
        exc ->
          message = Exception.message(exc)
          stack = Exception.format(:error, exc, __STACKTRACE__)
          Logger.error("[#{worker_id}] job #{job_id} FAILED:\n#{stack}")

          Benchmarks.submit_results(job, %{
            worker_id: worker_id,
            status: :failed,
            results: nil,
            error: message
          })

          {:error, message}
      end
    else
      {:error, reason} ->
        Logger.warning("[#{worker_id}] could not load job #{job_id}: #{inspect(reason)}")
        {:error, :job_not_found}
    end
  end

  defp worker_id do
    case System.get_env("WORKER_ID") do
      nil -> "worker-#{:inet.gethostname() |> elem(1)}"
      v -> v
    end
  end
end
