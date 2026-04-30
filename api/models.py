from typing import Optional, Any, Dict
from datetime import datetime
from pydantic import BaseModel


class BenchmarkConfig(BaseModel):
    """Configuration sent with a benchmark job."""
    duration_seconds: int = 60          # how long to run the benchmark
    executable: str = ""                # relative path to the executable inside the archive
    args: list[str] = []                # extra CLI args to pass to the game
    mock: bool = False                  # if True, worker simulates benchmark (no real game needed)
    resolution: str = "1920x1080"
    quality_preset: str = "high"
    exeConfig: str = ""


class JobCreate(BaseModel):
    game_name: str
    config: BenchmarkConfig = BenchmarkConfig()


class JobResponse(BaseModel):
    id: str
    status: str
    game_name: str
    config: Dict[str, Any]
    worker_id: Optional[str]
    results: Optional[Dict[str, Any]]
    error: Optional[str]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class WorkerResultPayload(BaseModel):
    """Payload a worker sends when a benchmark finishes."""
    worker_id: str
    status: str                          # "completed" or "failed"
    results: Optional[Dict[str, Any]]
    error: Optional[str] = None
