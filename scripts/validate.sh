#!/usr/bin/env bash
# validate.sh
# Validates the current Open WebUI deployment without changing anything.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_ROOT/docker"
COMPOSE_FILE="$COMPOSE_DIR/docker-compose.yml"

FAILED=0
WARNINGS=0

pass() {
    echo "[PASS] $1"
}

fail() {
    echo "[FAIL] $1"
    FAILED=$((FAILED + 1))
}

warn() {
    echo "[WARN] $1"
    WARNINGS=$((WARNINGS + 1))
}

compose() {
    if docker compose version >/dev/null 2>&1; then
        docker compose "$@"
    elif command -v docker-compose >/dev/null 2>&1; then
        docker-compose "$@"
    else
        return 127
    fi
}

echo "================================="
echo " Open WebUI Deployment Validation"
echo "================================="
echo

# 1. Docker service
if systemctl is-active --quiet docker 2>/dev/null; then
    pass "Docker service is running"
elif docker info >/dev/null 2>&1; then
    pass "Docker engine is available through Docker Desktop/WSL"
else
    fail "Docker engine is not running"
fi

# 2. Docker access
if docker info >/dev/null 2>&1; then
    pass "Docker is accessible"
else
    fail "Docker is not accessible"
fi

# 3. Docker Compose
if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose plugin is available"
elif command -v docker-compose >/dev/null 2>&1; then
    pass "docker-compose is available"
else
    fail "Docker Compose is not installed"
fi

# 4. Compose file
if [[ -f "$COMPOSE_FILE" ]]; then
    pass "docker-compose.yml exists"
else
    fail "docker-compose.yml was not found"
fi

# 5. Compose configuration
if [[ -f "$COMPOSE_FILE" ]]; then
    if (cd "$COMPOSE_DIR" && compose config >/dev/null 2>&1); then
        pass "Docker Compose configuration is valid"
    else
        fail "Docker Compose configuration is invalid"
    fi
fi

# 6. Open WebUI container
if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "open-webui"; then
    pass "open-webui container is running"
else
    fail "open-webui container is not running"
fi

# 7. Persistent storage
if docker inspect open-webui >/dev/null 2>&1; then
    if docker inspect \
        --format '{{range .Mounts}}{{println .Destination}}{{end}}' \
        open-webui 2>/dev/null |
        grep -qx "/app/backend/data"; then
        pass "Open WebUI persistent storage is attached"
    else
        fail "Persistent storage is not attached to /app/backend/data"
    fi
fi

# 8. Port 80
if command -v ss >/dev/null 2>&1; then
    if ss -lnt | grep -qE '[:.]80[[:space:]]'; then
        pass "HTTP port 80 is listening"
    else
        fail "HTTP port 80 is not listening"
    fi
else
    warn "ss command is unavailable; port check skipped"
fi

# 9. Open WebUI health endpoint
if command -v curl >/dev/null 2>&1; then
    HTTP_STATUS="$(
        curl -sS \
            --connect-timeout 5 \
            --max-time 10 \
            -o /dev/null \
            -w '%{http_code}' \
            http://localhost/health 2>/dev/null || true
    )"

    if [[ "$HTTP_STATUS" == "200" ]]; then
        pass "Open WebUI health endpoint returned HTTP 200"
    else
        fail "Open WebUI health endpoint returned ${HTTP_STATUS:-no response}"
    fi
else
    warn "curl is not installed; HTTP health check skipped"
fi

# 10. Environment configuration
if [[ -f "$COMPOSE_DIR/.env" ]]; then
    pass ".env file exists"
else
    warn ".env file not found; environment variables may be provided another way"
fi

echo
echo "================================="
echo "Result: $FAILED failed, $WARNINGS warnings"
echo "================================="

if (( FAILED > 0 )); then
    exit 1
fi

exit 0