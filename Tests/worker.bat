docker run -d ^
  -e BENCHMARKER_ROLE=worker ^
  -e DATABASE_URL=ecto://benchmarker:benchmarker@postgres/benchmarker ^
  -e SECRET_KEY_BASE=dev-secret-key-base-please-change-me-it-must-be-at-least-64-bytes-long-aaaaaaaaaaa ^
  --network benchmarker-infra_default ^
  ghcr.io/jarberg/benchmarker-worker:latest