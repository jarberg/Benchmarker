# Benchmarker — Phoenix + Ash server

The Elixir/Phoenix server that replaces the Python FastAPI app.

## Stack

- **Phoenix 1.7** (Bandit) on **Elixir 1.16 / OTP 26**
- **Ash 3.x** with `AshPostgres`, `AshJsonApi`, `AshPhoenix`, `AshOban`
- **Inertia.js** bridge serving a **React + shadcn/ui** SPA from `assets/`
- **Postgres 16** for persistence
- **Oban** for background jobs (replaces the Python RQ queue)

## Layout

```
server/
  config/                 mix configs (dev / prod / test / runtime)
  lib/
    benchmarker/          domain logic
      benchmarks.ex       Ash domain
      benchmarks/job.ex   Ash resource — jobs
      benchmarks/config.ex Ash resource — config presets
      workers/            Oban workers
    benchmarker_web/      Phoenix endpoint, router, controllers, layouts
  assets/                 Vite + React + Tailwind + shadcn/ui
  priv/repo/              migrations + seeds
  Dockerfile              multi-stage release image
  docker-compose.yml      local dev stack (Postgres + server)
```

## Local development

```bash
# 1. install Elixir + Erlang (asdf or your package manager) and Node 20+
# 2. start Postgres
docker compose up -d postgres

# 3. install deps and run migrations
mix setup

# 4. run the server (this also starts Vite via the watcher in dev.exs)
mix phx.server
```

The app is at <http://localhost:4000>.

Routes:

| Path                      | Purpose                                |
| ------------------------- | -------------------------------------- |
| `GET  /`                  | Inertia React dashboard                |
| `GET  /api/health`        | health check                           |
| `POST /api/jobs`          | multipart job submission               |
| `GET  /api/jobs/:id/file` | worker fetches the uploaded archive    |
| `POST /api/jobs/:id/results` | worker callback                     |
| `GET  /jsonapi/jobs`      | AshJsonApi — list / show / patch       |
| `GET  /jsonapi/configs`   | AshJsonApi — preset CRUD               |

## Production

The Dockerfile builds a release. Configure via env vars: `DATABASE_URL`,
`SECRET_KEY_BASE`, `PHX_HOST`, `PORT`, `UPLOAD_DIR`. See `../k8s/` for the
Kubernetes manifests and `../terraform/` for the AWS infrastructure that
provisions the cluster + RDS.
