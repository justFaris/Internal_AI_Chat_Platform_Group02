#!/usr/bin/env bash
# 12-cleanup.sh — Phase 12: full teardown of the deployed environment
#
# Run ON THE VM (app-level teardown):
#   ./12-cleanup.sh              stop the stack, keep Open WebUI data
#   ./12-cleanup.sh --data       also delete Open WebUI data and backups
#
# Run FROM YOUR MACHINE with --terraform (infrastructure teardown):
#   ./scripts/12-cleanup.sh --terraform
#
# Scope warning, and it matters:
#   The Terraform config manages the resource group itself, so
#   `terraform destroy` deletes EVERYTHING in that group -- including the
#   Azure OpenAI account, its model deployment, the Log Analytics workspace,
#   the action group and the alert rules, none of which are declared in
#   Terraform. They were created by hand and will NOT be recreated by
#   `terraform apply`. Phase 7 and phase 11 work has to be repeated.
set -euo pipefail

# --- infrastructure teardown (run from the machine holding the repo) ------
if [ "${1:-}" = "--terraform" ]; then
  cd "$(dirname "$0")/../terraform"
  cat <<'EOF'
About to run `terraform destroy`.

This deletes the whole resource group rg-openwebui, which also removes:
  - openwebui-aoai        (Azure OpenAI account + the gpt-5-mini deployment)
  - law-openwebui         (Log Analytics workspace)
  - dce-openwebui         (data collection endpoint)
  - ag-openwebui          (action group) and the 4 metric alert rules
None of those are in the Terraform config, so `terraform apply` will not
bring them back.

Make sure you have the Azure OpenUI key saved somewhere outside Azure, and
that /mnt/data/open-webui is backed up, before continuing.
EOF
  read -r -p "Type 'destroy' to continue: " CONFIRM
  if [ "$CONFIRM" != "destroy" ]; then
    echo "Aborted."
    exit 1
  fi
  terraform plan -destroy -out=tfplan
  terraform destroy -auto-approve tfplan
  echo "== Terraform destroy complete =="
  exit 0
fi

# --- application teardown (run on the VM) --------------------------------
cd "$(dirname "$0")/../docker"

if [ "${1:-}" = "--data" ]; then
  read -r -p "This deletes Open WebUI data and all backups under /mnt/data. Type 'yes' to continue: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
  fi
  echo "== Stopping the stack =="
  docker compose down -v
  sudo rm -rf /mnt/data/open-webui/* /mnt/data/backups/*
  echo "== Data and backups removed =="
else
  # A plain stop is the safe default: the database lives on the managed data
  # disk, and losing it means losing every chat and the admin account.
  echo "== Stopping the stack (data is kept) =="
  docker compose down
  echo "== To remove data as well, re-run with --data =="
fi

# --- optional: roll back host hardening -----------------------------------
if [ "${2:-}" = "--unharden" ]; then
  echo "== Removing host hardening =="
  sudo rm -f /etc/ssh/sshd_config.d/10-hardening.conf
  sudo sshd -t && sudo systemctl reload ssh
  sudo rm -f /etc/fail2ban/jail.d/sshd-hardening.local
  sudo systemctl disable --now fail2ban 2>/dev/null || true
  sudo rm -f /usr/local/sbin/apply-docker-user-rules.sh
  sudo systemctl disable --now ufw-docker-user.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/ufw-docker-user.service
  sudo ufw --force reset >/dev/null
  echo "== Hardening removed (UFW reset to inactive) =="
fi

echo
echo "== Done. To remove the Azure resources too, run:"
echo "   ./scripts/12-cleanup.sh --terraform   (from the machine with the repo)"
