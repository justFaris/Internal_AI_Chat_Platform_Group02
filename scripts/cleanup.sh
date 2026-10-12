#!/usr/bin/env bash
# cleanup.sh — Stop the Open WebUI stack safely.
#
# Usage:
#   ./cleanup.sh
#   ./cleanup.sh --images
#   ./cleanup.sh --delete-volume

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
COMPOSE_DIR="$PROJECT_ROOT/docker"

REMOVE_IMAGES=false
DELETE_VOLUME=false

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

for arg in "$@"; do
    case "$arg" in
        --images)
            REMOVE_IMAGES=true
            ;;
        --delete-volume)
            DELETE_VOLUME=true
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--images] [--delete-volume]"
            exit 2
            ;;
    esac
done

cd "$COMPOSE_DIR"

if $REMOVE_IMAGES; then
    echo "Stopping stack and removing images..."
    compose down --rmi all
else
    echo "Stopping stack..."
    compose down
fi

if $DELETE_VOLUME; then
    echo
    echo "WARNING: This will permanently delete Open WebUI data."
    read -r -p "Type DELETE to continue: " answer

    if [[ "$answer" == "DELETE" ]]; then
        compose down -v
        echo "Open WebUI volume deleted."
    else
        echo "Volume was kept."
    fi
fi

echo "Cleanup completed."