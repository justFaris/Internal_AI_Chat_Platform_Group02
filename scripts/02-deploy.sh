#!/usr/bin/env bash
# 02-deploy.sh — run from the repo's docker/ directory on the VM
set -euo pipefail

cd "$(dirname "$0")/../docker"

if [ ! -f .env ]; then
  echo "ERROR: docker/.env not found. Copy .env.example to .env and fill in real values." >&2
  exit 1
fi

echo "== Pulling images =="
docker compose pull

echo "== Starting stack =="
docker compose up -d

echo "== Status =="
docker compose ps
