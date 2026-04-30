"""
runners/unreal.py — Unreal Engine benchmark runner.

Launches the game with UE's built-in CSV profiler and Unreal Insights tracing,
then parses the CSV output from Saved/Profiling/CSV/ for per-frame metrics.

Expected CSV columns (UE 4.27 / UE 5.x):
  FrameTime, GameThreadTime, RenderThreadTime, GPUTime,
  DrawCalls, BasePassDrawCalls, Triangles, PhysicsTime, MemUsed_MB
"""

import os
import csv
import glob
import time
import shutil
import tempfile
import subprocess
import threading
import statistics
from datetime import datetime, timezone
from typing import Optional

import psutil

from runners.generic import MetricsCollector, extract_archive


# Flags appended to every UE launch for profiling
UE_PROFILE_FLAGS = [
    "-csvprofile",
    "-trace=cpu,gpu,frame,memory,bookmarks",
    "-nosplash",
    "-nopause",
    "-unattended",      # suppress dialogs
]


def run(job_id: str, file_path: str, config: dict) -> dict:
    """Run an Unreal Engine benchmark. Returns structured results dict."""
    duration   = config.get("duration_seconds", 60)
    executable = config.get("executable", "")
    extra_args = config.get("args", [])
    mock       = config.get("mock", False)

    started_at = datetime.now(timezone.utc).isoformat()

    if mock:
        return _run_mock(job_id, duration, config, started_at)
    return _run_real(job_id, file_path, executable, extra_args, duration, config, started_at)


# ─── mock ─────────────────────────────────────────────────────────────────────

def _run_mock(job_id: str, duration: int, config: dict, started_at: str) -> dict:
    import random

    print(f"[unreal-runner] Mock UE benchmark for job {job_id} ({duration}s)")

    collector = MetricsCollector()
    collector.start()

    frames = []
    for _ in range(duration * 2):
        frames.append({
            "frame_time_ms":    round(random.uniform(8, 20), 2),
            "game_thread_ms":   round(random.uniform(3, 10), 2),
            "render_thread_ms": round(random.uniform(4, 12), 2),
            "gpu_ms":           round(random.uniform(6, 18), 2),
            "draw_calls":       random.randint(800, 2400),
            "triangles":        random.randint(1_000_000, 4_000_000),
        })
        time.sleep(0.5)

    collector.stop()
    ended_at = datetime.now(timezone.utc).isoformat()
    return _build_result(started_at, ended_at, collector, frames, config, mode="mock")


# ─── real ─────────────────────────────────────────────────────────────────────

def _run_real(
    job_id: str,
    file_path: str,
    executable: str,
    extra_args: list,
    duration: int,
    config: dict,
    started_at: str,
) -> dict:
    with tempfile.TemporaryDirectory(prefix=f"ue_bench_{job_id}_") as tmpdir:
        print(f"[unreal-runner] Extracting {file_path} → {tmpdir}")
        extract_archive(file_path, tmpdir)

        exec_path = _find_ue_executable(tmpdir, executable)
        if not exec_path:
            raise FileNotFoundError(
                f"Could not find UE executable. Set 'executable' in config "
                f"(e.g. 'Binaries/Win64/MyGame.exe'). Searched: {tmpdir}"
            )

        game_dir    = os.path.dirname(exec_path)
        saved_dir   = _find_saved_dir(tmpdir)
        csv_out_dir = os.path.join(saved_dir, "Profiling", "CSV") if saved_dir else os.path.join(tmpdir, "Saved", "Profiling", "CSV")
        os.makedirs(csv_out_dir, exist_ok=True)

        cmd = [exec_path] + UE_PROFILE_FLAGS + extra_args
        res_str = config.get("resolution", "1920x1080")
        w, _, h = res_str.partition("x")
        if w and h:
            cmd += [f"-resx={w}", f"-resy={h}"]

        print(f"[unreal-runner] Launching: {' '.join(cmd)}")

        proc = subprocess.Popen(cmd, cwd=game_dir, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        collector = MetricsCollector(pid=proc.pid)
        collector.start()

        try:
            proc.wait(timeout=duration + 60)
        except subprocess.TimeoutExpired:
            proc.kill()

        collector.stop()

        # Give UE a moment to flush CSV
        time.sleep(2)
        frames = _parse_csv_output(csv_out_dir)

    ended_at = datetime.now(timezone.utc).isoformat()
    return _build_result(started_at, ended_at, collector, frames, config, mode="real")


# ─── CSV parsing ──────────────────────────────────────────────────────────────

# Map UE CSV column names → our internal names (handles minor version diffs)
COLUMN_MAP = {
    "frametime":        "frame_time_ms",
    "frame_time":       "frame_time_ms",
    "gamethreadtime":   "game_thread_ms",
    "gamethread":       "game_thread_ms",
    "renderthreadtime": "render_thread_ms",
    "renderthread":     "render_thread_ms",
    "gputime":          "gpu_ms",
    "gpu":              "gpu_ms",
    "drawcalls":        "draw_calls",
    "basepassdrawcalls":"draw_calls",
    "triangles":        "triangles",
    "physicstime":      "physics_ms",
    "memused_mb":       "memory_mb",
    "memused_mb":       "memory_mb",
}


def _parse_csv_output(csv_dir: str) -> list[dict]:
    """Find the newest CSV file in the output dir and parse it into a list of frame dicts."""
    csvs = glob.glob(os.path.join(csv_dir, "*.csv"))
    if not csvs:
        print(f"[unreal-runner] No CSV files found in {csv_dir}")
        return []

    newest = max(csvs, key=os.path.getmtime)
    print(f"[unreal-runner] Parsing CSV: {newest}")

    frames = []
    with open(newest, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            frame = {}
            for col, val in row.items():
                key = COLUMN_MAP.get(col.lower().strip())
                if key and val.strip():
                    try:
                        frame[key] = float(val.strip())
                    except ValueError:
                        pass
            if frame:
                frames.append(frame)

    print(f"[unreal-runner] Parsed {len(frames)} frames from CSV")
    return frames


# ─── result builder ───────────────────────────────────────────────────────────

def _build_result(
    started_at: str,
    ended_at: str,
    collector: MetricsCollector,
    frames: list[dict],
    config: dict,
    mode: str,
) -> dict:
    result = {
        "engine": "unreal",
        "mode": mode,
        "started_at": started_at,
        "ended_at": ended_at,
        "config": config,
        "system_info": {
            "cpu": {
                "logical_cores":  psutil.cpu_count(logical=True),
                "physical_cores": psutil.cpu_count(logical=False),
            },
            "total_memory_mb": round(psutil.virtual_memory().total / (1024 * 1024), 1),
        },
        "metrics": collector.summary(),
    }

    if frames:
        result["unreal"] = _summarise_frames(frames)

        # Derive FPS from frame time
        ft = [f["frame_time_ms"] for f in frames if f.get("frame_time_ms", 0) > 0]
        if ft:
            fps_vals = sorted([1000.0 / ms for ms in ft])
            p1_idx   = max(0, int(len(fps_vals) * 0.01))
            result["fps"] = {
                "avg":    round(statistics.mean(fps_vals), 1),
                "min":    round(fps_vals[0], 1),
                "max":    round(fps_vals[-1], 1),
                "p1_low": round(fps_vals[p1_idx], 1),
            }

    return result


def _summarise_frames(frames: list[dict]) -> dict:
    """Compute avg/p95/max for each metric across all frames."""
    keys = ["frame_time_ms", "game_thread_ms", "render_thread_ms", "gpu_ms",
            "draw_calls", "triangles", "physics_ms", "memory_mb"]

    summary = {"sample_count": len(frames)}
    for key in keys:
        vals = sorted([f[key] for f in frames if key in f])
        if not vals:
            continue
        p95_idx = int(len(vals) * 0.95)
        summary[key] = {
            "avg": round(statistics.mean(vals), 2),
            "p95": round(vals[p95_idx], 2),
            "max": round(vals[-1], 2),
            "min": round(vals[0], 2),
        }

    return summary


# ─── helpers ──────────────────────────────────────────────────────────────────

def _find_ue_executable(root: str, hint: str) -> Optional[str]:
    """Find the UE game executable. Uses hint if provided, otherwise searches."""
    if hint:
        p = os.path.join(root, hint)
        if os.path.exists(p):
            return p

    # Typical UE layout: GameName/Binaries/Win64/GameName.exe
    for pattern in ["**/Binaries/Win64/*.exe", "**/Binaries/Linux/*"]:
        matches = glob.glob(os.path.join(root, pattern), recursive=True)
        # Filter out shader compiler and crash reporter
        matches = [m for m in matches if not any(x in m for x in ["ShaderCompile", "CrashReport", "Unreal"])]
        if matches:
            return matches[0]

    # Fallback: any executable
    for r, _, files in os.walk(root):
        for f in files:
            p = os.path.join(r, f)
            if (f.endswith(".exe") or os.access(p, os.X_OK)) and not f.startswith("."):
                return p
    return None


def _find_saved_dir(root: str) -> Optional[str]:
    """Locate the game's Saved/ directory (may be nested under game name folder)."""
    for r, dirs, _ in os.walk(root):
        if "Saved" in dirs:
            return os.path.join(r, "Saved")
    return None
