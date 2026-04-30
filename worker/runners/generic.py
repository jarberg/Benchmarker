"""
runner.py — launches the game process and collects benchmark metrics.

Supports two modes:
  - Real mode:  extracts the game archive and runs the executable
  - Mock mode:  simulates a benchmark run (useful for testing the pipeline)
"""

import os
import time
import zipfile
import tarfile
import tempfile
import subprocess
import threading
import statistics
from typing import Optional
from datetime import datetime, timezone

import psutil


# --------------------------------------------------------------------------- #
#  Metrics collector                                                            #
# --------------------------------------------------------------------------- #

class MetricsCollector:
    """Samples CPU, memory, and (optionally) GPU usage in a background thread."""

    def __init__(self, pid: Optional[int] = None, interval: float = 0.5):
        self.pid = pid
        self.interval = interval
        self._running = False
        self._thread: Optional[threading.Thread] = None

        self.cpu_samples: list[float] = []
        self.mem_samples: list[float] = []   # MB
        self.fps_samples: list[float] = []   # placeholder — real games need frametimes

    def start(self):
        self._running = True
        self._thread = threading.Thread(target=self._collect, daemon=True)
        self._thread.start()

    def stop(self):
        self._running = False
        if self._thread:
            self._thread.join(timeout=5)

    def _collect(self):
        proc = psutil.Process(self.pid) if self.pid else None
        while self._running:
            try:
                if proc and proc.is_running():
                    self.cpu_samples.append(proc.cpu_percent(interval=None))
                    mem = proc.memory_info().rss / (1024 * 1024)
                    self.mem_samples.append(mem)
                else:
                    # System-wide fallback (used in mock mode)
                    self.cpu_samples.append(psutil.cpu_percent(interval=None))
                    self.mem_samples.append(psutil.virtual_memory().used / (1024 * 1024))
            except (psutil.NoSuchProcess, psutil.AccessDenied):
                break
            time.sleep(self.interval)

    def summary(self) -> dict:
        def safe_stats(samples):
            if not samples:
                return {"min": 0, "max": 0, "avg": 0, "p95": 0}
            sorted_s = sorted(samples)
            p95_idx = int(len(sorted_s) * 0.95)
            return {
                "min": round(min(sorted_s), 2),
                "max": round(max(sorted_s), 2),
                "avg": round(statistics.mean(sorted_s), 2),
                "p95": round(sorted_s[p95_idx], 2),
            }

        return {
            "cpu_percent": safe_stats(self.cpu_samples),
            "memory_mb": safe_stats(self.mem_samples),
            "sample_count": len(self.cpu_samples),
        }


# --------------------------------------------------------------------------- #
#  Archive extraction                                                           #
# --------------------------------------------------------------------------- #

def extract_archive(file_path: str, dest_dir: str) -> str:
    """Extract zip or tar.gz archive; return dest_dir."""
    if file_path.endswith(".zip"):
        with zipfile.ZipFile(file_path, "r") as z:
            z.extractall(dest_dir)
    elif file_path.endswith((".tar.gz", ".tgz", ".tar.bz2")):
        with tarfile.open(file_path) as t:
            t.extractall(dest_dir)
    else:
        # Assume it's a standalone executable — copy it directly
        import shutil
        dest = os.path.join(dest_dir, os.path.basename(file_path))
        shutil.copy2(file_path, dest)
        os.chmod(dest, 0o755)
    return dest_dir


# --------------------------------------------------------------------------- #
#  Main benchmark runner                                                        #
# --------------------------------------------------------------------------- #

def run_benchmark(job_id: str, file_path: str, config: dict) -> dict:
    """
    Run a benchmark job. Returns a results dict.

    config keys:
      duration_seconds  (int)    how long to run
      executable        (str)    relative path inside the extracted archive
      args              (list)   extra CLI args for the game
      mock              (bool)   if True, skip real launch and simulate
      resolution        (str)
      quality_preset    (str)
    """
    duration = config.get("duration_seconds", 60)
    executable = config.get("executable", "")
    extra_args = config.get("args", [])
    mock = config.get("mock", False)

    started_at = datetime.now(timezone.utc).isoformat()

    if mock:
        return _run_mock(job_id, duration, config, started_at)

    return _run_real(job_id, file_path, executable, extra_args, duration, config, started_at)


def _run_mock(job_id: str, duration: int, config: dict, started_at: str) -> dict:
    """Simulate a benchmark without launching a real game. Useful for CI/testing."""
    import random

    print(f"[worker] Mock benchmark for job {job_id}, running {duration}s simulation...")

    collector = MetricsCollector(pid=None)
    collector.start()

    # Simulate frame rendering
    fps_values = []
    steps = duration * 2  # sample every 0.5s
    for _ in range(steps):
        fps_values.append(round(random.uniform(55, 120), 1))
        time.sleep(0.5)

    collector.stop()

    ended_at = datetime.now(timezone.utc).isoformat()
    return _build_result(started_at, ended_at, collector, fps_values, config, mode="mock")


def _run_real(
    job_id: str,
    file_path: str,
    executable: str,
    extra_args: list,
    duration: int,
    config: dict,
    started_at: str,
) -> dict:
    """Extract archive, launch the executable, and collect metrics."""
    with tempfile.TemporaryDirectory(prefix=f"benchmark_{job_id}_") as tmpdir:
        print(f"[worker] Extracting {file_path} → {tmpdir}")
        extract_archive(file_path, tmpdir)

        # Locate executable
        exec_path = os.path.join(tmpdir, executable) if executable else _find_executable(tmpdir)
        if not exec_path or not os.path.exists(exec_path):
            raise FileNotFoundError(
                f"Executable not found. Set 'executable' in config. Looked for: {exec_path}"
            )
        os.chmod(exec_path, 0o755)

        cmd = [exec_path] + extra_args
        print(f"[worker] Launching: {' '.join(cmd)}")

        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=os.path.dirname(exec_path),
        )

        collector = MetricsCollector(pid=proc.pid)
        collector.start()

        try:
            proc.wait(timeout=duration + 30)
        except subprocess.TimeoutExpired:
            proc.kill()

        collector.stop()

    ended_at = datetime.now(timezone.utc).isoformat()
    # Real FPS requires the game to output frametimes — placeholder here
    fps_values = []
    return _build_result(started_at, ended_at, collector, fps_values, config, mode="real")


def _find_executable(directory: str) -> Optional[str]:
    """Find the first executable file in the extracted directory."""
    for root, _, files in os.walk(directory):
        for f in files:
            path = os.path.join(root, f)
            if os.access(path, os.X_OK) and not f.startswith("."):
                return path
    return None


def _build_result(
    started_at: str,
    ended_at: str,
    collector: MetricsCollector,
    fps_values: list,
    config: dict,
    mode: str,
) -> dict:
    system = psutil.virtual_memory()
    cpu_info = {
        "logical_cores": psutil.cpu_count(logical=True),
        "physical_cores": psutil.cpu_count(logical=False),
    }

    result = {
        "mode": mode,
        "started_at": started_at,
        "ended_at": ended_at,
        "config": config,
        "system_info": {
            "cpu": cpu_info,
            "total_memory_mb": round(system.total / (1024 * 1024), 1),
        },
        "metrics": collector.summary(),
    }

    if fps_values:
        sorted_fps = sorted(fps_values)
        result["fps"] = {
            "min": round(min(sorted_fps), 1),
            "max": round(max(sorted_fps), 1),
            "avg": round(statistics.mean(sorted_fps), 1),
            "p1_low": round(sorted_fps[max(0, int(len(sorted_fps) * 0.01))], 1),
        }

    return result
