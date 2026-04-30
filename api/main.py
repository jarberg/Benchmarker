from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from database import init_db
from routes.jobs import router as jobs_router
from routes.configs import router as configs_router

app = FastAPI(
    title="Game Benchmark API",
    description="Submit games for automated benchmarking across scalable worker machines.",
    version="0.1.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
def startup():
    init_db()


app.include_router(jobs_router)
app.include_router(configs_router)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/")
def root():
    return {
        "service": "Game Benchmark API",
        "docs": "/docs",
        "endpoints": {
            "submit_job": "POST /jobs",
            "list_jobs": "GET /jobs",
            "get_configs": "GET /configs",
            "get_job": "GET /jobs/{id}",
            "get_results": "GET /jobs/{id} (check results field)",
        },
    }
