#!/usr/bin/env bash
# 03-validate.sh — basic health checks after deployment
set -euo pipefail

cd "$(dirname "$0")/../docker"

echo "== Container status =="
docker compose ps

echo "== Open WebUI internal health check =="
if docker compose exec -T open-webui curl -fsS http://localhost:8080/health >/dev/null; then
  echo "OK: open-webui is responding internally."
else
  echo "FAIL: open-webui did not respond. Check: docker compose logs open-webui" >&2
  exit 1
fi

echo "== Caddy is listening on 443 =="
if curl -fsSk https://localhost >/dev/null; then
  echo "OK: reverse proxy is serving HTTPS."
else
  echo "FAIL: Caddy did not respond. Check: docker compose logs caddy" >&2
  exit 1
fi

echo "== Data disk in use =="
df -h /mnt/data

echo "== All checks passed =="
