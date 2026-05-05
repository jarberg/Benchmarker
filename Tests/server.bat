docker run -d ^
  -e PHX_HOST=localhost ^
  -e PHX_SERVER=true ^
  -e PORT=4001 ^
  -e DATABASE_URL=ecto://benchmarker:benchmarker@postgres/benchmarker ^
  -e SECRET_KEY_BASE=dev-secret-key-base-please-change-me-it-must-be-at-least-64-bytes-long-aaaaaaaaaaa ^
  -p 4001:4001 ^
  --network benchmarker_default ^
  ghcr.io/jarberg/benchmarker:latest