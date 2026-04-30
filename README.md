# Benchmarker

Submit games for automated benchmarking across scalable workers.

## Stack

| Layer            | Tech                                                                |
| ---------------- | ------------------------------------------------------------------- |
| Backend          | **Elixir / Phoenix 1.7** + **Ash 3** (AshPostgres, AshJsonApi, AshOban) |
| Frontend         | **React 18** via **Inertia.js**, styled with **shadcn/ui** + Tailwind |
| Database         | **PostgreSQL 16** (RDS in production via AshPostgres)               |
| Background jobs  | **Oban** (Postgres-backed) — runs the engine-specific runners       |
| Container        | Multi-stage **Docker** release image                                |
| Orchestration    | **Kubernetes** (EKS) with Kustomize overlays                        |
| Continuous deploy| **Argo CD** (app-of-apps pattern, GitOps)                           |
| Infrastructure   | **Terraform** — VPC, EKS, RDS, ECR, ArgoCD bootstrap                |

## Repo layout

```
.
├── server/        Phoenix + Ash app (replaces api/)
│   ├── lib/       domain + web layer
│   ├── assets/    Vite + React + shadcn/ui frontend
│   └── Dockerfile release image
│
├── k8s/           Kubernetes manifests
│   ├── base/      Deployment, Service, Ingress, Secrets, PVC, HPA
│   └── overlays/  staging / production overrides
│
├── argocd/        ArgoCD AppProject + app-of-apps + per-env Applications
│
├── terraform/     AWS infrastructure (VPC, EKS, RDS, ECR, ArgoCD helm)
│
├── api/           [legacy] Python FastAPI service — superseded by server/
├── frontend/      [legacy] Vite + React app — superseded by server/assets/
├── worker/        [legacy] Python RQ worker — superseded by Benchmarker.Workers.*
└── client/        Python CLI client
```

## Local dev

The new Elixir stack:

```bash
cd server
docker compose up -d postgres   # start Postgres on :5433
mix setup                       # deps + migrations + seeds
mix phx.server                  # http://localhost:4000
```

The legacy Python stack (still works while you migrate):

```bash
docker compose up -d            # repo root — postgres + redis + api + worker
```

## Deploy

1. **Provision infra** — `cd terraform && terraform init && terraform apply`. This creates the VPC, EKS cluster, RDS Postgres, ECR repo, and bootstraps ArgoCD into the cluster.
2. **Build & push the image** — `docker build -t <ecr_url>:v0.1.0 server/ && docker push ...`
3. **GitOps takes over** — ArgoCD reconciles `argocd/applications/*.yaml`, which pulls `k8s/overlays/{staging,production}` into the cluster. Push to `main` → ArgoCD auto-syncs.

## Worker roles

The same release image runs in two roles, controlled by `BENCHMARKER_ROLE`:

- **`web`** (default) — boots the Phoenix endpoint and Oban queues. Good for low-traffic clusters where the API host can also drive benchmarks.
- **`worker`** — boots Oban only, no HTTP listener. Run these on dedicated benchmark hosts (GPU nodes in a real environment) so long-running runs don't tie up API capacity.

In `k8s/base/`, `deployment.yaml` runs the web role and `worker-deployment.yaml` runs `BENCHMARKER_ROLE=worker`. Both pull the same image. Scale the worker deployment to control concurrency.

## Domain

Two Ash resources port the original SQLAlchemy models 1:1:

- **`Benchmarker.Benchmarks.Job`** — game_name, file_path, status, config, results, error, worker_id, timestamps
- **`Benchmarker.Benchmarks.Config`** — saved benchmark presets (name + JSON config)

Endpoints:

- `GET /` — Inertia-rendered React dashboard
- `POST /api/jobs` — multipart upload (legacy-compatible with the old FastAPI route)
- `POST /api/jobs/:id/results` — worker callback
- `GET /jsonapi/{jobs,configs}` — JSON:API courtesy of AshJsonApi
