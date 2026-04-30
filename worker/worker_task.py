"""
worker_task.py — the function enqueued by rq.

rq workers import and call run_benchmark(job_id) from this module.
"""

import os
import tempfile
import traceback

import httpx

from runner import run_benchmark as _run_benchmark

API_URL = os.getenv("API_URL", "http://localhost:8000")
WORKER_ID = os.getenv("WORKER_ID", "worker-unknown")


def run_benchmark(job_id: str):
    """
    Entry point called by rq for each benchmark job.
    1. Fetch job details from API
    2. Download game file
    3. Run benchmark
    4. POST results back to API
    """
    print(f"[{WORKER_ID}] Starting job {job_id}")

    # Mark job as running
    _patch_status(job_id, "running")

    try:
        # 1. Fetch job metadata
        job = _get_job(job_id)
        config = job.get("config", {})

        # 2. Download game file (unless mock mode)
        if config.get("mock", False):
            file_path = ""
        else:
            file_path = _download_game(job_id)

        # 3. Run benchmark
        results = _run_benchmark(job_id, file_path, config)

        # 4. Submit results
        _submit_results(job_id, status="completed", results=results)
        print(f"[{WORKER_ID}] Job {job_id} completed successfully.")

    except Exception as exc:
        error_msg = traceback.format_exc()
        print(f"[{WORKER_ID}] Job {job_id} FAILED:\n{error_msg}")
        _submit_results(job_id, status="failed", results=None, error=str(exc))
        raise


def _get_job(job_id: str) -> dict:
    r = httpx.get(f"{API_URL}/jobs/{job_id}", timeout=10)
    r.raise_for_status()
    return r.json()


def _patch_status(job_id: str, status: str):
    """Directly update job status via results endpoint with minimal payload."""
    try:
        httpx.post(
            f"{API_URL}/jobs/{job_id}/results",
            json={"worker_id": WORKER_ID, "status": status, "results": None},
            timeout=10,
        )
    except Exception:
        pass  # Don't fail the job if the status ping fails


def _download_game(job_id: str) -> str:
    """Download the game file for a job into a temp file. Returns file path."""
    r = httpx.get(f"{API_URL}/jobs/{job_id}/file", timeout=120, follow_redirects=True)
    r.raise_for_status()

    # Determine extension from content-disposition or fallback
    content_disp = r.headers.get("content-disposition", "")
    ext = ".bin"
    if "filename=" in content_disp:
        fname = content_disp.split("filename=")[-1].strip().strip('"')
        _, ext = os.path.splitext(fname)

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
    tmp.write(r.content)
    tmp.close()
    print(f"[{WORKER_ID}] Downloaded game to {tmp.name} ({len(r.content) / 1024:.1f} KB)")
    return tmp.name


def _submit_results(job_id: str, status: str, results: dict | None, error: str = None):
    payload = {
        "worker_id": WORKER_ID,
        "status": status,
        "results": results,
        "error": error,
    }
    r = httpx.post(f"{API_URL}/jobs/{job_id}/results", json=payload, timeout=30)
    r.raise_for_status()
