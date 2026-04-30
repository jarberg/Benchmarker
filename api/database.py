import os
import uuid
import enum
from datetime import datetime

from sqlalchemy import create_engine, Column, String, DateTime, JSON, Text
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./benchmark.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in DATABASE_URL else {},
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class JobStatus(str, enum.Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class Config(Base):
    __tablename__ = "config"

    id     = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    name   = Column(String, nullable=True)   # human-readable preset name
    config = Column(JSON, default=dict)

class Job(Base):
    __tablename__ = "jobs"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    status = Column(String, default=JobStatus.PENDING)

    game_name = Column(String, nullable=False)
    file_path = Column(String, nullable=False)  # path to uploaded game archive
    config = Column(JSON, default=dict)          # benchmark config (duration, args, etc.)

    worker_id = Column(String, nullable=True)    # which worker picked this up
    results = Column(JSON, nullable=True)        # metrics collected by worker
    error = Column(Text, nullable=True)          # error message if failed


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def init_db():
    Base.metadata.create_all(bind=engine)
