defmodule Benchmarker.Workers.Runners do
  @moduledoc """
  Dispatch benchmark execution to the right engine runner. Mirrors
  `worker/runner.py` in the legacy Python service.
  """

  alias Benchmarker.Workers.Runners.{Generic, Unity, Unreal}

  @callback run(job_id :: String.t(), file_path :: String.t() | nil, config :: map(), args :: list()) :: map()

  @spec run(String.t(), String.t() | nil, map(), list()) :: map()
  def run(job_id, file_path, config, args \\ []) do
    runner =
      config
      |> Map.get("exeConfig", "generic")
      |> to_string()
      |> String.downcase()
      |> module_for()

    runner.run(job_id, file_path, config, args)
  end

  defp module_for("unreal"), do: Unreal
  defp module_for("unity"), do: Unity
  defp module_for(_), do: Generic
end
