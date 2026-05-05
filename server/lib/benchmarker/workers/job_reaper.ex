defmodule Benchmarker.Workers.JobReaper do
  @moduledoc """
  Periodic Oban job that finds benchmark jobs stuck in `:running` state past
  the timeout window and marks them as `:failed`.

  This handles the case where a worker process dies or is killed before it can
  update the job status itself (e.g. OOM kill, `docker stop`, node crash).
  """

  use Oban.Worker, queue: :benchmarks

  alias Benchmarker.Benchmarks
  import Ecto.Query

  require Logger

  # Reap jobs that have been :running longer than the benchmark timeout plus a
  # 5-minute grace period, so healthy long-running jobs aren't touched.
  @grace_ms 5 * 60 * 1_000

  @impl Oban.Worker
  def perform(_job) do
    timeout_ms = Application.get_env(:benchmarker, :benchmark_timeout_ms, 3_600_000)
    cutoff = DateTime.add(DateTime.utc_now(), -(timeout_ms + @grace_ms), :millisecond)

    stale_jobs =
      Benchmarker.Repo.all(
        from j in Benchmarker.Benchmarks.Job,
          where: j.status == :running and j.updated_at < ^cutoff
      )

    Enum.each(stale_jobs, fn job ->
      Logger.warning("[reaper] job #{job.id} stuck in :running since #{job.updated_at} — marking failed")

      Benchmarks.submit_results(job, %{
        worker_id: job.worker_id,
        status: :failed,
        results: nil,
        error: "Worker terminated before job could complete"
      })
    end)

    Logger.info("[reaper] reaped #{length(stale_jobs)} stale job(s)")
    :ok
  end
end
