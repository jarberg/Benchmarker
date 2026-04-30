import os
import json
import shutil
import uuid
from typing import List, Optional

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, BackgroundTasks
from sqlalchemy.orm import Session
from rq import Queue
import redis

from database import get_db, Job, JobStatus
from models import JobResponse, WorkerResultPayload

router = APIRouter(prefix="/jobs", tags=["jobs"])

UPLOAD_DIR = os.getenv("UPLOAD_DIR", "./uploads")
REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")

redis_conn = redis.from_url(REDIS_URL)
q = Queue("benchmark", connection=redis_conn)

os.makedirs(UPLOAD_DIR, exist_ok=True)


@router.post("", response_model=JobResponse, status_code=201)
async def create_job(
    game_name: str = Form(...),
    config: str = Form("{}"),          # JSON string of BenchmarkConfig
    file: UploadFile = File(...),
    db: Session = Depends(get_db),
):
    """
    Submit a new benchmark job. Upload the game archive and config together.
    The file can be a .zip, .tar.gz, or a standalone executable.
    """
    # Parse config JSON
    try:
        config_dict = json.loads(config)
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="config must be valid JSON")

    # Save uploaded file
    job_id = str(uuid.uuid4())
    ext = os.path.splitext(file.filename)[1] if file.filename else ".bin"
    file_path = os.path.join(UPLOAD_DIR, f"{job_id}{ext}")
    with open(file_path, "wb") as f:
        shutil.copyfileobj(file.file, f)

    # Create job record
    job = Job(
        id=job_id,
        game_name=game_name,
        file_path=file_path,
        config=config_dict,
        status=JobStatus.PENDING,
    )
    db.add(job)
    db.commit()
    db.refresh(job)

    # Enqueue job ID to Redis
    q.enqueue("worker_task.run_benchmark", job_id, job_timeout=600)

    return job


@router.get("", response_model=List[JobResponse])
def list_jobs(
    status: Optional[str] = None,
    limit: int = 50,
    db: Session = Depends(get_db),
):
    """List all benchmark jobs, optionally filtered by status."""
    query = db.query(Job)
    if status:
        query = query.filter(Job.status == status)
    return query.order_by(Job.created_at.desc()).limit(limit).all()


@router.get("/{job_id}", response_model=JobResponse)
def get_job(job_id: str, db: Session = Depends(get_db)):
    """Get a single job by ID."""
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    return job


@router.get("/{job_id}/file")
def get_job_file(job_id: str, db: Session = Depends(get_db)):
    """Download the game file for a job (used by workers)."""
    from fastapi.responses import FileResponse

    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    if not os.path.exists(job.file_path):
        raise HTTPException(status_code=404, detail="Game file not found on disk")
    return FileResponse(job.file_path, filename=os.path.basename(job.file_path))


@router.post("/{job_id}/results", response_model=JobResponse)
def submit_results(
    job_id: str,
    payload: WorkerResultPayload,
    db: Session = Depends(get_db),
):
    """
    Called by workers to submit benchmark results or report failure.
    """
    job = db.query(Job).filter(Job.id == job_id).first()
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")

    job.worker_id = payload.worker_id
    job.status = payload.status
    job.results = payload.results
    job.error = payload.error

    from datetime import datetime
    job.updated_at = datetime.utcnow()

    db.commit()
    db.refresh(job)
    return job
