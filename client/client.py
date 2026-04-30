"""
client.py — thin wrapper around the Benchmark API.
"""

import json
from pathlib import Path
from typing import Optional

import httpx


class BenchmarkClient:
    def __init__(self, api_url: str = "http://localhost:8000"):
        self.api_url = api_url.rstrip("/")
        self._http = httpx.Client(base_url=self.api_url, timeout=120, trust_env=False)

    # ------------------------------------------------------------------ #
    def submit(
        self,
        game_path: Path,
        game_name: str,
        config: dict,
    ) -> dict:
        """Upload a game file and create a benchmark job."""
        with open(game_path, "rb") as f:
            response = self._http.post(
                "/jobs",
                data={
                    "game_name": game_name,
                    "config": json.dumps(config),
                },
                files={"file": (game_path.name, f, "application/octet-stream")},
            )
        response.raise_for_status()
        return response.json()

    def get(self, job_id: str) -> dict:
        r = self._http.get(f"/jobs/{job_id}")
        r.raise_for_status()
        return r.json()

    def list_jobs(self, status: Optional[str] = None, limit: int = 20) -> list:
        params = {"limit": limit}
        if status:
            params["status"] = status
        r = self._http.get("/jobs", params=params)
        r.raise_for_status()
        return r.json()

    def health(self) -> dict:
        r = self._http.get("/health")
        r.raise_for_status()
        return r.json()
