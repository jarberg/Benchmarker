defmodule Benchmarker.Workers.Runners.Unreal do
  @moduledoc """
  Unreal Engine runner. Launches the game with UE's CSV profiler and Insights
  tracing flags, then parses the latest CSV in `Saved/Profiling/CSV/` for
  per-frame thread/GPU times. Port of `worker/runners/unreal.py`.
  """

  @behaviour Benchmarker.Workers.Runners

  alias Benchmarker.Workers.{Archive, MetricsCollector}
  alias Benchmarker.Workers.Runners.Generic

  NimbleCSV.define(__MODULE__.CSVParser, separator: ",", escape: "\"")

  @profile_flags [
    "-csvprofile",
    "-trace=cpu,gpu,frame,memory,bookmarks",
    "-nosplash",
    "-nopause",
    "-unattended"
  ]

  @column_map %{
    "frametime" => "frame_time_ms",
    "frame_time" => "frame_time_ms",
    "gamethreadtime" => "game_thread_ms",
    "gamethread" => "game_thread_ms",
    "renderthreadtime" => "render_thread_ms",
    "renderthread" => "render_thread_ms",
    "gputime" => "gpu_ms",
    "gpu" => "gpu_ms",
    "drawcalls" => "draw_calls",
    "basepassdrawcalls" => "draw_calls",
    "triangles" => "triangles",
    "physicstime" => "physics_ms",
    "memused_mb" => "memory_mb"
  }

  @impl true
  def run(job_id, file_path, config, args \\ []) do
    duration = Map.get(config, "duration_seconds", 60)
    extra_args = if args != [], do: args, else: Map.get(config, "args", [])
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
    IO.puts("[unreal-runner] mock UE job #{job_id} for #{duration}s")
    {:ok, collector} = MetricsCollector.start_link(os_pid: nil)

    frames =
      for _ <- 1..(duration * 2) do
        Process.sleep(500)

        %{
          "frame_time_ms" => Float.round(:rand.uniform() * 12 + 8, 2),
          "game_thread_ms" => Float.round(:rand.uniform() * 7 + 3, 2),
          "render_thread_ms" => Float.round(:rand.uniform() * 8 + 4, 2),
          "gpu_ms" => Float.round(:rand.uniform() * 12 + 6, 2),
          "draw_calls" => :rand.uniform(1600) + 800,
          "triangles" => :rand.uniform(3_000_000) + 1_000_000
        }
      end

    summary = MetricsCollector.stop_and_summarize(collector)
    ended_at = DateTime.utc_now() |> DateTime.to_iso8601()
    log = "[unreal-runner] mock UE run completed for job #{job_id} (#{duration}s simulated)"

    build_result(started_at, ended_at, summary, frames, config, "mock", log)
  end

  # ── real ────────────────────────────────────────────────────────────────

  defp run_real(job_id, file_path, executable, extra_args, duration, config, started_at) do
    tmp = Path.join(System.tmp_dir!(), "ue_bench_#{job_id}")
    File.mkdir_p!(tmp)
    {:ok, _} = Archive.extract(file_path, tmp)

    exec_path = find_ue_executable(tmp, executable)

    unless exec_path do
      raise "Could not find UE executable. Set 'executable' (e.g. Binaries/Win64/MyGame.exe). Searched: #{tmp}"
    end

    csv_dir =
      case find_saved_dir(tmp) do
        nil -> Path.join([tmp, "Saved", "Profiling", "CSV"])
        saved -> Path.join([saved, "Profiling", "CSV"])
      end

    File.mkdir_p!(csv_dir)

    {res_w, res_h} = parse_resolution(Map.get(config, "resolution", "1920x1080"))

    args =
      @profile_flags ++ Enum.map(extra_args, &to_string/1) ++ ["-resx=#{res_w}", "-resy=#{res_h}"]

    port =
      Port.open({:spawn_executable, exec_path}, [
        :binary,
        :exit_status,
        cd: Path.dirname(exec_path),
        args: args
      ])

    os_pid =
      case Port.info(port, :os_pid) do
        {:os_pid, p} -> p
        _ -> nil
      end

    {:ok, collector} = MetricsCollector.start_link(os_pid: os_pid)
    {_exit, log} = wait_for_exit(port, duration + 60)
    summary = MetricsCollector.stop_and_summarize(collector)

    # Give UE a moment to flush CSV
    Process.sleep(2_000)
    frames = parse_csv_output(csv_dir)

    ended_at = DateTime.utc_now() |> DateTime.to_iso8601()
    File.rm_rf(tmp)

    build_result(started_at, ended_at, summary, frames, config, "real", log)
  end

  defp wait_for_exit(port, timeout_s, acc \\ "") do
    receive do
      {^port, {:data, chunk}} ->
        wait_for_exit(port, timeout_s, acc <> chunk)

      {^port, {:exit_status, code}} ->
        {code, acc}
    after
      timeout_s * 1_000 ->
        Port.close(port)
        {:timeout, acc}
    end
  end

  defp parse_resolution(s) do
    case String.split(s, "x") do
      [w, h] -> {w, h}
      _ -> {"1920", "1080"}
    end
  end

  # ── CSV parsing ─────────────────────────────────────────────────────────

  @doc false
  def parse_csv_output(csv_dir) do
    case Path.wildcard(Path.join(csv_dir, "*.csv")) do
      [] ->
        IO.puts("[unreal-runner] no CSV in #{csv_dir}")
        []

      paths ->
        newest = Enum.max_by(paths, &File.stat!(&1).mtime)
        IO.puts("[unreal-runner] parsing #{newest}")
        parse_csv_file(newest)
    end
  end

  defp parse_csv_file(path) do
    [headers | rows] =
      path
      |> File.stream!()
      |> __MODULE__.CSVParser.parse_stream(skip_headers: false)
      |> Enum.to_list()

    keys = Enum.map(headers, fn h -> Map.get(@column_map, String.downcase(String.trim(h))) end)

    Enum.flat_map(rows, fn row ->
      frame =
        keys
        |> Enum.zip(row)
        |> Enum.reduce(%{}, fn
          {nil, _}, acc ->
            acc

          {_, ""}, acc ->
            acc

          {k, v}, acc ->
            case Float.parse(String.trim(v)) do
              {f, _} -> Map.put(acc, k, f)
              _ -> acc
            end
        end)

      if frame == %{}, do: [], else: [frame]
    end)
  end

  # ── result builder ──────────────────────────────────────────────────────

  defp build_result(started_at, ended_at, summary, frames, config, mode, log \\ "") do
    base = %{
      "engine" => "unreal",
      "mode" => mode,
      "started_at" => started_at,
      "ended_at" => ended_at,
      "config" => config,
      "system_info" => Generic.system_info(),
      "metrics" => summary,
      "log" => log
    }

    if frames == [] do
      base
    else
      base
      |> Map.put("unreal", summarise_frames(frames))
      |> maybe_put_fps(frames)
    end
  end

  defp maybe_put_fps(result, frames) do
    fps =
      frames
      |> Enum.map(&Map.get(&1, "frame_time_ms", 0))
      |> Enum.filter(&(&1 > 0))
      |> Enum.map(&(1000.0 / &1))
      |> Enum.sort()

    case fps do
      [] ->
        result

      _ ->
        n = length(fps)
        p1_idx = max(0, trunc(n * 0.01))

        Map.put(result, "fps", %{
          "avg" => Float.round(Enum.sum(fps) / n, 1),
          "min" => Float.round(List.first(fps), 1),
          "max" => Float.round(List.last(fps), 1),
          "p1_low" => Float.round(Enum.at(fps, p1_idx), 1)
        })
    end
  end

  @keys ~w(frame_time_ms game_thread_ms render_thread_ms gpu_ms draw_calls triangles physics_ms memory_mb)

  defp summarise_frames(frames) do
    base = %{"sample_count" => length(frames)}

    Enum.reduce(@keys, base, fn key, acc ->
      vals =
        frames
        |> Enum.map(&Map.get(&1, key))
        |> Enum.filter(&is_number/1)
        |> Enum.sort()

      case vals do
        [] ->
          acc

        _ ->
          n = length(vals)
          p95_idx = max(0, trunc(n * 0.95) - 1)

          Map.put(acc, key, %{
            "avg" => Float.round(Enum.sum(vals) / n, 2),
            "p95" => Float.round(Enum.at(vals, p95_idx) * 1.0, 2),
            "max" => Float.round(List.last(vals) * 1.0, 2),
            "min" => Float.round(List.first(vals) * 1.0, 2)
          })
      end
    end)
  end

  # ── filesystem helpers ──────────────────────────────────────────────────

  defp find_ue_executable(root, hint) when is_binary(hint) and hint != "" do
    candidate = Path.join(root, hint)
    if File.exists?(candidate), do: candidate, else: find_ue_executable(root, "")
  end

  defp find_ue_executable(root, _hint) do
    candidates =
      Path.wildcard(Path.join(root, "**/Binaries/Win64/*.exe")) ++
        Path.wildcard(Path.join(root, "**/Binaries/Linux/*"))

    candidates
    |> Enum.reject(fn p ->
      Enum.any?(["ShaderCompile", "CrashReport", "Unreal"], &String.contains?(p, &1))
    end)
    |> List.first() || Archive.find_first_executable(root)
  end

  defp find_saved_dir(root) do
    Path.wildcard(Path.join(root, "**/Saved")) |> Enum.find(&File.dir?/1)
  end
end
