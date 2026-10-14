#!/usr/bin/env bash
# 99-cleanup.sh — stop the stack. Pass --volumes to also delete application data.
set -euo pipefail

cd "$(dirname "$0")/../docker"

if [ "${1:-}" = "--volumes" ]; then
  read -r -p "This deletes Open WebUI data under /mnt/data/open-webui and the Caddy volumes. Type 'yes' to continue: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
  docker compose down -v
  sudo rm -rf /mnt/data/open-webui/*
else
  docker compose down
fi

echo "== Done =="
