#!/usr/bin/env python3
"""
cli.py — Command-line interface for the Game Benchmark System.

Usage examples:
  # Submit a real game (zip archive)
  python cli.py submit my_game.zip --name "MyGame" --duration 60 --executable bin/game

  # Submit a mock job (no real game needed — tests the pipeline)
  python cli.py submit --mock --name "TestRun"

  # Check status
  python cli.py status <job-id>

  # View results
  python cli.py results <job-id>

  # List all jobs
  python cli.py list
  python cli.py list --status pending
"""

import json
import sys
import time
from pathlib import Path
from typing import Optional

import click
from client import BenchmarkClient

API_URL_DEFAULT = "http://localhost:8000"

# ANSI colours
GREEN = "\033[92m"
YELLOW = "\033[93m"
RED = "\033[91m"
CYAN = "\033[96m"
BOLD = "\033[1m"
RESET = "\033[0m"

STATUS_COLORS = {
    "pending": YELLOW,
    "running": CYAN,
    "completed": GREEN,
    "failed": RED,
}


def colored_status(status: str) -> str:
    color = STATUS_COLORS.get(status, "")
    return f"{color}{status}{RESET}"


def fmt_json(data: dict) -> str:
    return json.dumps(data, indent=2, default=str)


@click.group()
@click.option("--api", default=API_URL_DEFAULT, envvar="BENCHMARK_API_URL", help="API server URL")
@click.pass_context
def cli(ctx, api):
    """Game Benchmark CLI — submit and monitor benchmark jobs."""
    ctx.ensure_object(dict)
    ctx.obj["client"] = BenchmarkClient(api_url=api)


# ------------------------------------------------------------------ #
#  submit                                                              #
# ------------------------------------------------------------------ #

@cli.command()
@click.argument("game_file", required=False, type=click.Path(exists=True, path_type=Path))
@click.option("--name", "-n", required=False, help="Human-readable name for this game/run")
@click.option("--duration", "-d", default=60, show_default=True, help="Benchmark duration in seconds")
@click.option("--executable", "-e", default="", help="Relative path to executable inside the archive")
@click.option("--args", "-a", multiple=True, help="Extra args to pass to the game (repeatable)")
@click.option("--mock", is_flag=True, default=False, help="Run a mock benchmark (no real game needed)")
@click.option("--resolution", default="1920x1080", show_default=True)
@click.option("--quality", default="high", show_default=True)
@click.option("--wait", "-w", is_flag=True, default=False, help="Wait for results before exiting")
@click.pass_context
def submit(ctx, game_file, name, duration, executable, args, mock, resolution, quality, wait):
    """Submit a game for benchmarking.

    GAME_FILE is the path to a .zip / .tar.gz archive or standalone executable.
    In --mock mode, GAME_FILE is optional.
    """
    client: BenchmarkClient = ctx.obj["client"]

    if not mock and not game_file:
        raise click.UsageError("GAME_FILE is required unless --mock is set.")

    if not name:
        name = game_file.stem if game_file else "mock-run"

    config = {
        "duration_seconds": duration,
        "executable": executable,
        "args": list(args),
        "mock": mock,
        "resolution": resolution,
        "quality_preset": quality,
    }

    # For mock mode, we still need to upload *something* (API requires a file)
    # Use a tiny placeholder if no file given
    if mock and not game_file:
        import tempfile
        tmp = Path(tempfile.mktemp(suffix=".bin"))
        tmp.write_bytes(b"mock")
        game_file = tmp

    click.echo(f"\n{BOLD}Submitting benchmark job...{RESET}")
    click.echo(f"  Game : {name}")
    click.echo(f"  File : {game_file}")
    click.echo(f"  Mode : {'mock (simulated)' if mock else 'real'}")
    click.echo(f"  Duration: {duration}s\n")

    try:
        job = client.submit(game_file, name, config)
    except Exception as e:
        click.echo(f"{RED}Error submitting job: {e}{RESET}", err=True)
        sys.exit(1)

    job_id = job["id"]
    click.echo(f"{GREEN}✓ Job created:{RESET} {BOLD}{job_id}{RESET}")
    click.echo(f"\nCheck status:   benchmark status {job_id}")
    click.echo(f"View results:   benchmark results {job_id}")

    if wait:
        click.echo(f"\n{CYAN}Waiting for results...{RESET}")
        _wait_for_job(client, job_id)


# ------------------------------------------------------------------ #
#  status                                                              #
# ------------------------------------------------------------------ #

@cli.command()
@click.argument("job_id")
@click.pass_context
def status(ctx, job_id):
    """Get the current status of a benchmark job."""
    client: BenchmarkClient = ctx.obj["client"]
    try:
        job = client.get(job_id)
    except Exception as e:
        click.echo(f"{RED}Error: {e}{RESET}", err=True)
        sys.exit(1)

    _print_job_summary(job)


# ------------------------------------------------------------------ #
#  results                                                             #
# ------------------------------------------------------------------ #

@cli.command()
@click.argument("job_id")
@click.option("--json", "output_json", is_flag=True, help="Output raw JSON")
@click.pass_context
def results(ctx, job_id, output_json):
    """View benchmark results for a completed job."""
    client: BenchmarkClient = ctx.obj["client"]
    try:
        job = client.get(job_id)
    except Exception as e:
        click.echo(f"{RED}Error: {e}{RESET}", err=True)
        sys.exit(1)

    if output_json:
        click.echo(fmt_json(job))
        return

    _print_job_summary(job)

    if job["status"] == "failed":
        click.echo(f"\n{RED}Error:{RESET} {job.get('error', 'Unknown error')}")
        return

    if job["status"] != "completed":
        click.echo(f"\n{YELLOW}Results not yet available. Status: {job['status']}{RESET}")
        return

    res = job.get("results", {})
    if not res:
        click.echo(f"\n{YELLOW}No results data.{RESET}")
        return

    click.echo(f"\n{BOLD}── Results ──────────────────────────{RESET}")
    click.echo(f"  Mode     : {res.get('mode', 'N/A')}")
    click.echo(f"  Started  : {res.get('started_at', 'N/A')}")
    click.echo(f"  Ended    : {res.get('ended_at', 'N/A')}")

    sys_info = res.get("system_info", {})
    if sys_info:
        click.echo(f"\n{BOLD}── System ───────────────────────────{RESET}")
        cpu = sys_info.get("cpu", {})
        click.echo(f"  CPU cores: {cpu.get('physical_cores')} physical / {cpu.get('logical_cores')} logical")
        click.echo(f"  RAM total: {sys_info.get('total_memory_mb', 0):.0f} MB")

    metrics = res.get("metrics", {})
    if metrics:
        click.echo(f"\n{BOLD}── Performance Metrics ─────────────{RESET}")
        cpu_m = metrics.get("cpu_percent", {})
        mem_m = metrics.get("memory_mb", {})
        click.echo(f"  CPU usage  avg={cpu_m.get('avg')}%  p95={cpu_m.get('p95')}%  max={cpu_m.get('max')}%")
        click.echo(f"  Memory     avg={mem_m.get('avg')} MB  max={mem_m.get('max')} MB")
        click.echo(f"  Samples    : {metrics.get('sample_count')}")

    fps = res.get("fps")
    if fps:
        click.echo(f"\n{BOLD}── FPS ──────────────────────────────{RESET}")
        click.echo(f"  Avg FPS   : {fps.get('avg')}")
        click.echo(f"  Min FPS   : {fps.get('min')}")
        click.echo(f"  Max FPS   : {fps.get('max')}")
        click.echo(f"  1% Low    : {fps.get('p1_low')}")


# ------------------------------------------------------------------ #
#  list                                                                #
# ------------------------------------------------------------------ #

@cli.command("list")
@click.option("--status", "-s", default=None, help="Filter by status (pending/running/completed/failed)")
@click.option("--limit", "-l", default=20, show_default=True)
@click.pass_context
def list_jobs(ctx, status, limit):
    """List benchmark jobs."""
    client: BenchmarkClient = ctx.obj["client"]
    try:
        jobs = client.list_jobs(status=status, limit=limit)
    except Exception as e:
        click.echo(f"{RED}Error: {e}{RESET}", err=True)
        sys.exit(1)

    if not jobs:
        click.echo("No jobs found.")
        return

    click.echo(f"\n{'ID':<38} {'STATUS':<12} {'GAME':<24} {'WORKER':<20} CREATED")
    click.echo("─" * 110)
    for j in jobs:
        status_str = colored_status(j["status"])
        worker = j.get("worker_id") or "—"
        created = j["created_at"][:19].replace("T", " ")
        click.echo(f"{j['id']:<38} {status_str:<20} {j['game_name']:<24} {worker:<20} {created}")


# ------------------------------------------------------------------ #
#  helper: wait for job                                                #
# ------------------------------------------------------------------ #

def _wait_for_job(client: BenchmarkClient, job_id: str, poll_interval: int = 3):
    terminal = {"completed", "failed"}
    while True:
        job = client.get(job_id)
        s = job["status"]
        click.echo(f"  Status: {colored_status(s)}", nl=True)
        if s in terminal:
            return job
        time.sleep(poll_interval)


def _print_job_summary(job: dict):
    click.echo(f"\n{BOLD}Job {job['id']}{RESET}")
    click.echo(f"  Status : {colored_status(job['status'])}")
    click.echo(f"  Game   : {job['game_name']}")
    click.echo(f"  Worker : {job.get('worker_id') or '(not yet assigned)'}")
    click.echo(f"  Created: {job['created_at'][:19].replace('T', ' ')}")


if __name__ == "__main__":
    cli()
