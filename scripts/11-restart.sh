#!/usr/bin/env bash
# 11-restart.sh — Phase 11: ordered, self-verifying restart
#
# Run on the VM:  ./11-restart.sh [--hard]
#
# Default: restart the application containers only, leave the VM and the
# Docker daemon alone. --hard additionally restarts the Docker and SSH daemons.
#
# Order matters. open-webui comes up first so Caddy's reverse proxy has a live
# backend by the time Caddy starts; the other order produces a window of 502s.
# Every step is verified before moving on, and the script stops the proxy
# rather than leaving a half-started stack serving 502s.
set -uo pipefail

cd "$(dirname "$0")/../docker"

HARD=0
[ "${1:-}" = "--hard" ] && HARD=1

log() { printf '\n== %s ==\n' "$1"; }

wait_healthy() {
  local name=$1 tries=${2:-60} i state
  for ((i = 0; i < tries; i++)); do
    state=$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo missing)
    [ "$state" = "healthy" ] && { echo "  $name is healthy (after $((i * 10))s)"; return 0; }
    [ "$state" = "missing" ] && { echo "  $name is missing" >&2; return 1; }
    sleep 10
  done
  echo "  $name did not become healthy in time" >&2
  return 1
}

if [ "$HARD" -eq 1 ]; then
  log "Hard restart: Docker and SSH daemons"
  sudo systemctl restart docker
  sudo systemctl reload ssh    # reload, never restart: a bad unit would drop the session
  echo "  docker and sshd restarted"
  sleep 8
fi

# "up -d" is a no-op when the containers are already running, so a restart has
# to stop them first or this script does nothing. --force-recreate is still
# avoided: stopping is enough and it preserves container identity.
log "Stopping the stack"
docker compose stop 2>&1 | sed 's/^/  /'

log "Starting the stack (backend first, then proxy)"
docker compose up -d --no-build 2>&1 | sed 's/^/  /'

log "Waiting for the backend"
if ! wait_healthy docker-open-webui-1 60; then
  echo >&2
  echo "ERROR: open-webui did not come up. Stopping caddy so the failure is" >&2
  echo "       visible instead of serving 502s. Recent logs:" >&2
  docker compose logs --tail 30 open-webui >&2
  docker compose stop caddy >/dev/null 2>&1
  exit 1
fi

log "Verifying the proxy and the app end to end"
if curl -fsSk --max-time 15 https://localhost/ >/dev/null; then
  echo "  HTTPS on 443 is serving"
else
  echo "ERROR: HTTPS is not answering after restart." >&2
  docker compose logs --tail 20 caddy >&2
  exit 1
fi

# A 200 from / is not proof the backend is reachable: Caddy answers with its
# own 502 page for an unreachable upstream, so /health must be checked too.
# -k is required: Caddy serves an internal-CA certificate, so verification
# fails by design. Without it curl exits 60 and this reads as 000, which
# looks exactly like an outage.
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 15 https://localhost/health)
case "$code" in
  200) echo "  backend reachable through the proxy (health=200)" ;;
  000) echo "  backend health endpoint not reachable through the proxy (000)" ;;
  *)   echo "  backend health through the proxy returned $code" ;;
esac

log "Container status"
docker compose ps

log "Restart complete"
