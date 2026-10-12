#!/usr/bin/env bash
# restart.sh — Restart Open WebUI and validate the deployment.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_ROOT/docker"

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        echo "Docker Compose is not installed"
        exit 1
    fi
}

echo "Restarting Open WebUI..."

cd "$COMPOSE_DIR"

case "${1:-}" in
    --recreate)
        compose up -d --force-recreate
        ;;
    "")
        compose restart open-webui
        ;;
    *)
        echo "Usage: $0 [--recreate]"
        exit 2
        ;;
esac

echo "Waiting for Open WebUI..."

for _ in $(seq 1 30); do
    if docker ps --format '{{.Names}}' | grep -qx "open-webui"; then
        if curl -fsS http://localhost/health >/dev/null 2>&1; then
            break
        fi
    fi
    sleep 5
done

echo "Running validation..."

"$SCRIPT_DIR/validate.sh"