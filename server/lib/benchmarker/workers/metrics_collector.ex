defmodule Benchmarker.Workers.MetricsCollector do
  @moduledoc """
  Background sampler for an OS process. Periodically reads CPU% and RSS for the
  given OS pid via `ps` (POSIX) and accumulates samples until `summary/1` is
  called. Mirrors the original `MetricsCollector` from `worker/runners/generic.py`.

  When `:os_pid` is `nil`, the collector falls back to the host's overall CPU
  (the legacy mock-mode behaviour).
  """

  use GenServer

  require Logger

  @type sample :: number()

  defstruct os_pid: nil,
            interval_ms: 500,
            cpu_samples: [],
            mem_samples: []

  # ── public api ────────────────────────────────────────────────────────────

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @doc "Stop sampling and return a summary."
  def stop_and_summarize(pid) when is_pid(pid) do
    GenServer.call(pid, :summarize, 60_000)
  end

  # ── server ────────────────────────────────────────────────────────────────

  @impl GenServer
  def init(opts) do
    state = %__MODULE__{
      os_pid: Keyword.get(opts, :os_pid),
      interval_ms: Keyword.get(opts, :interval_ms, 500)
    }

    schedule(state.interval_ms)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:tick, state) do
    {cpu, mem_mb} = sample(state.os_pid)

    new_state = %{
      state
      | cpu_samples: [cpu | state.cpu_samples],
        mem_samples: [mem_mb | state.mem_samples]
    }

    schedule(state.interval_ms)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call(:summarize, _from, state) do
    summary = %{
      "cpu_percent" => stats(state.cpu_samples),
      "memory_mb" => stats(state.mem_samples),
      "sample_count" => length(state.cpu_samples)
    }

    {:stop, :normal, summary, state}
  end

  # ── helpers ───────────────────────────────────────────────────────────────

  defp schedule(ms), do: Process.send_after(self(), :tick, ms)

  # Posix `ps` works for both Linux and macOS. Windows benchmark hosts will
  # need `wmic`/`Get-CimInstance`; not implemented here but easy to slot in.
  defp sample(nil) do
    # Whole-host fallback for mock runs.
    case System.cmd("ps", ["-A", "-o", "%cpu,rss"], stderr_to_stdout: true) do
      {output, 0} -> aggregate_lines(output)
      _ -> {0.0, 0.0}
    end
  rescue
    _ -> {0.0, 0.0}
  end

  defp sample(os_pid) when is_integer(os_pid) do
    case System.cmd("ps", ["-p", Integer.to_string(os_pid), "-o", "%cpu=,rss="],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case String.split(String.trim(output), ~r/\s+/, trim: true) do
          [cpu, rss_kb] -> {to_float(cpu), to_float(rss_kb) / 1024.0}
          _ -> {0.0, 0.0}
        end

      _ ->
        {0.0, 0.0}
    end
  rescue
    _ -> {0.0, 0.0}
  end

  defp aggregate_lines(output) do
    output
    |> String.split("\n", trim: true)
    |> tl()
    |> Enum.reduce({0.0, 0.0}, fn line, {cpu_acc, mem_acc} ->
      case String.split(String.trim(line), ~r/\s+/, trim: true) do
        [cpu, rss] -> {cpu_acc + to_float(cpu), mem_acc + to_float(rss) / 1024.0}
        _ -> {cpu_acc, mem_acc}
      end
    end)
  end

  defp to_float(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> 0.0
    end
  end

  defp stats([]), do: %{"min" => 0, "max" => 0, "avg" => 0, "p95" => 0}

  defp stats(samples) do
    sorted = Enum.sort(samples)
    n = length(sorted)
    p95_idx = max(0, trunc(n * 0.95) - 1)

    %{
      "min" => round2(List.first(sorted)),
      "max" => round2(List.last(sorted)),
      "avg" => round2(Enum.sum(sorted) / n),
      "p95" => round2(Enum.at(sorted, p95_idx))
    }
  end

  defp round2(n), do: Float.round(n * 1.0, 2)
end
