defmodule Benchmarker.Workers.Runners.Unity do
  @moduledoc """
  Unity runner — currently a thin shim over Generic. Extend this with
  Unity-specific launch flags and Unity Profiler binary log parsing once
  a Unity build is available for testing.

  Unity launch flags worth wiring up later:
    -profiler-enable
    -profiler-log-file Saved/profiler_output.raw
    -screen-width 1920 -screen-height 1080
    -screen-fullscreen 0
  """

  @behaviour Benchmarker.Workers.Runners

  alias Benchmarker.Workers.Runners.Generic

  @impl true
  def run(job_id, file_path, config, args \\ []) do
    IO.puts(
      "[unity-runner] no Unity-specific profiling yet — falling back to generic for #{job_id}"
    )

    job_id
    |> Generic.run(file_path, config, args)
    |> Map.put("engine", "unity")
  end
end
