defmodule Benchmarker.Workers.Runners.Generic do
  @moduledoc """
  Engine-agnostic runner. Extracts the archive, launches the executable, and
  samples CPU/memory while it runs. Port of `worker/runners/generic.py`.
  """

  @behaviour Benchmarker.Workers.Runners

  alias Benchmarker.Workers.{Archive, MetricsCollector}

  @impl true
  def run(job_id, file_path, config) do
    duration = Map.get(config, "duration_seconds", 60)
    extra_args = Map.get(config, "args", [])
    executable = Map.get(config, "executable", "")
    mock? = Map.get(config, "mock", false)

    started_at = DateTime.utc_now() |> DateTime.to_iso8601()

    if mock? do
      run_mock(job_id, duration, config, started_at)
    else
      run_real(job_id, file_path, executable, extra_args, duration, config, started_at)
    end
  end

  # ── mock ────────────────────────────────────────────────────────────────

  defp run_mock(job_id, duration, config, started_at) do
    IO.puts("[generic-runner] mock job #{job_id} for #{duration}s")
    {:ok, collector} = MetricsCollector.start_link(os_pid: nil)

    fps =
      for _ <- 1..(duration * 2) do
        Process.sleep(500)
        Float.round(:rand.uniform() * 65 + 55, 1)
      end

    summary = MetricsCollector.stop_and_summarize(collector)
    ended_at = DateTime.utc_now() |> DateTime.to_iso8601()

    build_result(started_at, ended_at, summary, fps, config, "mock")
  end

  # ── real ────────────────────────────────────────────────────────────────

  defp run_real(job_id, file_path, executable, extra_args, duration, config, started_at) do
    tmp = Path.join(System.tmp_dir!(), "benchmark_#{job_id}")
    File.mkdir_p!(tmp)

    {:ok, _} = Archive.extract(file_path, tmp)

    exec_path =
      case executable do
        "" -> Archive.find_first_executable(tmp)
        rel -> Path.join(tmp, rel)
      end

    if is_nil(exec_path) or not File.exists?(exec_path) do
      raise "Executable not found. Set 'executable' in config. Looked for: #{inspect(exec_path)}"
    end

    File.chmod!(exec_path, 0o755)

    port =
      Port.open({:spawn_executable, exec_path}, [
        :binary,
        :exit_status,
        cd: Path.dirname(exec_path),
        args: Enum.map(extra_args, &to_string/1)
      ])

    os_pid = port_os_pid(port)
    {:ok, collector} = MetricsCollector.start_link(os_pid: os_pid)

    wait_for_exit(port, duration + 30)
    summary = MetricsCollector.stop_and_summarize(collector)

    ended_at = DateTime.utc_now() |> DateTime.to_iso8601()
    File.rm_rf(tmp)

    build_result(started_at, ended_at, summary, [], config, "real")
  end

  # ── helpers ─────────────────────────────────────────────────────────────

  defp port_os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} -> pid
      _ -> nil
    end
  end

  defp wait_for_exit(port, timeout_s) do
    receive do
      {^port, {:exit_status, _code}} -> :ok
    after
      timeout_s * 1_000 ->
        Port.close(port)
        :timeout
    end
  end

  @doc false
  def build_result(started_at, ended_at, summary, fps_values, config, mode) do
    base = %{
      "mode" => mode,
      "started_at" => started_at,
      "ended_at" => ended_at,
      "config" => config,
      "system_info" => system_info(),
      "metrics" => summary
    }

    if fps_values != [] do
      sorted = Enum.sort(fps_values)
      n = length(sorted)
      p1 = Enum.at(sorted, max(0, trunc(n * 0.01)))

      Map.put(base, "fps", %{
        "min" => List.first(sorted),
        "max" => List.last(sorted),
        "avg" => Float.round(Enum.sum(sorted) / n, 1),
        "p1_low" => p1
      })
    else
      base
    end
  end

  @doc false
  def system_info do
    %{
      "cpu" => %{
        "logical_cores" => System.schedulers_online(),
        "physical_cores" => :erlang.system_info(:logical_processors_available)
      },
      "total_memory_mb" => total_memory_mb()
    }
  end

  defp total_memory_mb do
    try do
      :memsup.get_system_memory_data()
      |> Keyword.get(:total_memory, 0)
      |> Kernel./(1024 * 1024)
      |> Float.round(1)
    rescue
      _ -> 0.0
    end
  end
end
