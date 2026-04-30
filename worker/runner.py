"""
runner.py - dispatch to the correct engine-specific runner based on exeConfig.

Supported engines:
  unreal  - runners/unreal.py   (CSV profiler + Unreal Insights)
  unity   - runners/unity.py    (stub - extend with Unity Profiler output)
  generic - runners/generic.py  (psutil only, any executable)
"""


def run_benchmark(job_id: str, file_path: str, config: dict) -> dict:
    exe_config = config.get("exeConfig", "generic").lower()

    if exe_config == "unreal":
        from runners.unreal import run
    elif exe_config == "unity":
        from runners.unity import run
    else:
        from runners.generic import run_benchmark as run

    return run(job_id, file_path, config)
