#!/usr/bin/env bash
# 00-prepare.sh — run once on the VM (idempotent: safe to re-run)
set -euo pipefail

MOUNT_POINT="/mnt/data"

echo "== System update =="
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install -y ufw unattended-upgrades ca-certificates curl gnupg lsb-release

echo "== Unattended security upgrades =="
sudo dpkg-reconfigure -f noninteractive unattended-upgrades

echo "== Host firewall (defense in depth; NSG already restricts by IP) =="
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable

echo "== Find and mount the data disk =="
if findmnt "$MOUNT_POINT" >/dev/null 2>&1; then
  echo "Already mounted at $MOUNT_POINT, skipping."
else
  # Pick the first disk that has no partitions and no filesystem yet.
  CANDIDATE=""
  for dev in /dev/nvme?n? /dev/sd?; do
    [ -e "$dev" ] || continue
    # skip the OS disk: it has partitions
    if lsblk -no NAME "$dev" | wc -l | grep -q '^1$'; then
      if ! sudo blkid "$dev" >/dev/null 2>&1; then
        CANDIDATE="$dev"
        break
      fi
    fi
  done

  if [ -z "$CANDIDATE" ]; then
    echo "ERROR: no empty, unpartitioned disk found. Run 'lsblk' and check manually." >&2
    exit 1
  fi

  echo "Using data disk: $CANDIDATE"
  sudo mkfs.ext4 -L openwebui-data "$CANDIDATE"
  sudo mkdir -p "$MOUNT_POINT"
  UUID=$(sudo blkid -s UUID -o value "$CANDIDATE")

  if ! grep -q "$UUID" /etc/fstab; then
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
  fi

  sudo systemctl daemon-reload
  sudo mount -a
fi

df -h "$MOUNT_POINT"
sudo mkdir -p "$MOUNT_POINT/open-webui"
sudo chown -R "$USER":"$USER" "$MOUNT_POINT"

echo "== Done. Data directory: $MOUNT_POINT/open-webui =="
