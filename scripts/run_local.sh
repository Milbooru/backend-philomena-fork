#!/usr/bin/env bash
# Run Philomena locally using podman containers for backing services.
# Usage:
#   First time:    bash scripts/run_local.sh --setup
#   Subsequent:    bash scripts/run_local.sh

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

source .env.local

SETUP=${1:-}

# Wait for PostgreSQL to be ready
echo "[1/4] Waiting for PostgreSQL..."
for i in {1..20}; do
  PGPASSWORD=postgres pg_isready -h localhost -U postgres -q && break || sleep 1
done
PGPASSWORD=postgres pg_isready -h localhost -U postgres || { echo "ERROR: PostgreSQL not ready"; exit 1; }
echo "PostgreSQL ready"

# Wait for OpenSearch to be ready
echo "[2/4] Waiting for OpenSearch..."
for i in {1..30}; do
  curl -sf http://localhost:9200 > /dev/null && break || sleep 2
done
curl -sf http://localhost:9200 > /dev/null && echo "OpenSearch ready" || echo "Warning: OpenSearch may not be ready"

# Fetch mix dependencies
echo "[3/4] Fetching mix deps..."
mix deps.get

if [[ "$SETUP" == "--setup" ]]; then
  echo "[4/4] Setting up database (first-time)..."
  # Install JS assets for the Philomena frontend
  (cd assets && npm install --silent)
  mix ecto.setup_dev
  echo ""
  echo "Database setup complete."
else
  echo "[4/4] Running any pending migrations..."
  mix ecto.migrate
fi

echo ""
echo "Starting Philomena on http://localhost:4000"
exec mix phx.server
