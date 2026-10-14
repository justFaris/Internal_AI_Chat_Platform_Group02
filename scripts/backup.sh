#!/usr/bin/env bash
# backup.sh — back up the Open WebUI data directory (/mnt/data/open-webui)
# Usage:
#   ./scripts/backup.sh                 create a new backup
#   ./scripts/backup.sh --restore FILE  restore from a backup archive
#   ./scripts/backup.sh --list          list existing backups
set -euo pipefail

DATA_DIR="/mnt/data/open-webui"
BACKUP_DIR="/mnt/data/backups"
KEEP=7   # how many recent backups to keep; older ones are pruned automatically
COMPOSE_FILE="$(cd "$(dirname "$0")/.." && pwd)/docker/docker-compose.yml"

mkdir -p "$BACKUP_DIR"

usage() {
  echo "Usage: $0 [--restore FILE | --list]" >&2
  exit 1
}

list_backups() {
  echo "== Available backups in $BACKUP_DIR =="
  ls -lh "$BACKUP_DIR"/openwebui-backup-*.tar.gz 2>/dev/null || echo "(none yet)"
}

do_backup() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local archive="$BACKUP_DIR/openwebui-backup-$ts.tar.gz"

  echo "== Stopping open-webui for a consistent backup =="
  docker compose -f "$COMPOSE_FILE" stop open-webui

  echo "== Archiving $DATA_DIR =="
  tar -czf "$archive" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")"

  echo "== Restarting open-webui =="
  docker compose -f "$COMPOSE_FILE" start open-webui

  echo "== Backup created: $archive =="
  du -h "$archive"

  echo "== Pruning old backups (keeping last $KEEP) =="
  # shellcheck disable=SC2012
  ls -1t "$BACKUP_DIR"/openwebui-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    echo "Removing $old"
    rm -f "$old"
  done

  list_backups
}

do_restore() {
  local archive="$1"
  if [ ! -f "$archive" ]; then
    echo "ERROR: backup file not found: $archive" >&2
    exit 1
  fi

  read -r -p "This replaces the current contents of $DATA_DIR with $archive. Type 'yes' to continue: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi

  echo "== Stopping open-webui =="
  docker compose -f "$COMPOSE_FILE" stop open-webui

  echo "== Backing up current data to a safety copy first =="
  local safety
  safety="$BACKUP_DIR/pre-restore-safety-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$safety" -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")"
  echo "Safety copy: $safety"

  echo "== Clearing current data directory =="
  rm -rf "${DATA_DIR:?}"/*

  echo "== Extracting $archive =="
  tar -xzf "$archive" -C "$(dirname "$DATA_DIR")"

  echo "== Restarting open-webui =="
  docker compose -f "$COMPOSE_FILE" start open-webui

  echo "== Restore complete. Verify in the browser that chats are back. =="
}

case "${1:-}" in
  --list)
    list_backups
    ;;
  --restore)
    [ $# -eq 2 ] || usage
    do_restore "$2"
    ;;
  "")
    do_backup
    ;;
  *)
    usage
    ;;
esac
