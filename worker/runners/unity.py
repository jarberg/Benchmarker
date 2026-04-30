"""
runners/unity.py — Unity benchmark runner (stub).

Unity profiling integration points:
  - Unity Profiler: launch with -profiler-enable -profiler-log-file output.raw
  - Memory Profiler package: captures heap snapshots
  - Frame Timing Stats: Application.targetFrameRate + FrameTimingManager

TODO: parse Unity profiler binary log or use the Unity Profiler Analyzer CLI
      once a Unity build is available for testing.
"""

from runners.generic import run_benchmark as _generic_run


def run(job_id: str, file_path: str, config: dict) -> dict:
    """
    Unity runner — currently falls back to generic psutil profiling.
    Extend this with Unity-specific launch flags and output parsing.
    """
    print(f"[unity-runner] Unity-specific profiling not yet implemented — falling back to generic runner for job {job_id}")

    # Unity launch flags to add when implementing:
    #   -profiler-enable
    #   -profiler-log-file Saved/profiler_output.raw
    #   -screen-width 1920 -screen-height 1080
    #   -screen-fullscreen 0

    result = _generic_run(job_id, file_path, config)
    result["engine"] = "unity"
    return result
