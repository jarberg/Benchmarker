"""
agent.py — the long-running worker process.

Run this on every benchmark machine. It connects to Redis and listens
for jobs on the "benchmark" queue. Scale by running this on more machines.

Usage:
    REDIS_URL=redis://localhost:6379 API_URL=http://localhost:8000 python agent.py
"""

import os
import sys
import socket
import logging
from rq import Worker, Queue, Connection
import redis

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger(__name__)

REDIS_URL = os.getenv("REDIS_URL", "redis://localhost:6379")
WORKER_ID = os.getenv("WORKER_ID", f"worker-{socket.gethostname()}")

# Set worker ID so worker_task.py can read it
os.environ["WORKER_ID"] = WORKER_ID


def main():
    log.info(f"Starting benchmark worker: {WORKER_ID}")
    log.info(f"Connecting to Redis: {REDIS_URL}")

    conn = redis.from_url(REDIS_URL)

    # Verify Redis connection
    try:
        conn.ping()
        log.info("Redis connection OK")
    except redis.ConnectionError as e:
        log.error(f"Cannot connect to Redis: {e}")
        sys.exit(1)

    queues = [Queue("benchmark", connection=conn)]

    log.info(f"Listening on queue: benchmark")
    log.info("Ready to accept benchmark jobs. Press Ctrl+C to stop.")

    with Connection(conn):
        worker = Worker(queues, connection=conn, name=WORKER_ID)
        worker.work(with_scheduler=False)


if __name__ == "__main__":
    main()
