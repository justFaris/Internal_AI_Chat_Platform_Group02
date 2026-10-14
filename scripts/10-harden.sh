#!/usr/bin/env bash
# 10-harden.sh — Phase 10: host hardening
#
# Run as the regular admin user on the VM:
#   sudo ./10-harden.sh <allowed-cidr> [<allowed-cidr> ...]
#
# Several CIDRs may be given, space separated. That matters when the admin's
# ISP hands out a dynamic public IP: a single /32 allow-list silently locks
# you out the moment the address changes, from both the NSG and the host
# firewall at the same time.
#
# Every step is idempotent, so re-running is safe. The script is written to
# avoid lockout: SSH is reloaded only after `sshd -t` accepts the new config,
# and the firewall's allow rules are added before any deny-all is applied.
#
# Do NOT run this from a session you cannot reconnect from until step 1 has
# been verified from a second terminal.
set -euo pipefail

ALLOWED_CIDRS="${*:?usage: sudo $0 <allowed-cidr> [<allowed-cidr> ...] e.g. 203.0.113.10/32}"
read -r -a CIDR_LIST <<< "$ALLOWED_CIDRS"
echo "== Phase 10 hardening (allowed CIDRs: ${ALLOWED_CIDRS}) =="

# One rule per CIDR: a single UFW rule cannot express multiple sources.
ufw_allow_ssh()   { for c in "${CIDR_LIST[@]}"; do ufw allow from "$c" to any port 22  proto tcp comment "ssh allowlist"   >/dev/null; done; }
ufw_allow_https() { for c in "${CIDR_LIST[@]}"; do ufw allow from "$c" to any port 443 proto tcp comment "https allowlist" >/dev/null; done; }

# ---------------------------------------------------------------- 1. SSH --
# Everything the VM needs from SSH: key auth, and TCP forwarding for the
# tunnel in phase 6. No root, no passwords, no X11, fewer guesses.
cat > /etc/ssh/sshd_config.d/10-hardening.conf <<'EOF'
# Managed by scripts/10-harden.sh -- phase 10
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
# Needed for the phase 6 SSH tunnel to reach Caddy on the VM's 443.
AllowTcpForwarding yes
EOF

# `sshd -t` refuses to run without its privilege separation directory, and
# that directory only exists once sshd has actually started. This script is
# also run from `az vm run-command`, where sshd is socket-activated and
# /run/sshd may be missing entirely -- which would abort the whole run.
mkdir -p /run/sshd && chmod 0755 /run/sshd

if ! sshd -t; then
  echo "ERROR: sshd rejected the new config; leaving sshd untouched." >&2
  rm -f /etc/ssh/sshd_config.d/10-hardening.conf
  exit 1
fi
# Ubuntu 24.04 socket-activates SSH, so ssh.service is never "active" and a
# plain reload fails -- which aborts the run under `set -e`. Restarting the
# socket is safe (it does not drop established sessions) and guarantees new
# connections read the hardened config.
if systemctl is-active --quiet ssh; then
  systemctl reload ssh
  echo "OK: sshd config valid and reloaded."
else
  systemctl restart ssh.socket
  echo "OK: sshd config valid (socket-activated; socket restarted)."
fi

# Key auth must actually work before we trust it. Bail out loudly if the
# admin's authorized_keys went missing -- that would lock everyone out.
keys=$(find /home -maxdepth 3 -name authorized_keys -type f 2>/dev/null | wc -l)
nonempty=$(find /home -maxdepth 3 -name authorized_keys -type f -size +0 2>/dev/null | wc -l)
if [ "$keys" -eq 0 ] || [ "$nonempty" -eq 0 ]; then
  echo "ERROR: no non-empty authorized_keys found -- SSH access would be lost." >&2
  exit 1
fi
echo "OK: ${nonempty} authorized_keys file(s) present."

# ------------------------------------------------------------- 2. UFW --
# The NSG already restricts 22/443 to the allowlist. UFW mirrors that so the
# host also stands on its own (defence in depth, and it covers traffic that
# never reaches the NSG, e.g. a future VNet peering).

ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw default deny routed >/dev/null
# Allow rules first, deny-by-default is already in force, so order is safe.
ufw_allow_ssh
ufw_allow_https
ufw --force enable >/dev/null
echo "OK: UFW enabled (22 + 443 restricted to ${ALLOWED_CIDRS})."

# Docker bypasses UFW. A published container port is DNAT'd in PREROUTING and
# then ACCEPTed by the DOCKER chain, which is reached before the INPUT chain
# that UFW manages -- so "ufw allow 443 from <ip>" never gets a say on
# container-published ports. The DOCKER-USER chain is the documented hook
# that runs before the DOCKER chain, so the allowlist is enforced there too.
# Without this, the only thing protecting 443 is the NSG.
# Rules are applied one at a time on purpose. `iptables-restore` without
# --noflush replaces the WHOLE filter table, which silently destroys UFW's
# rules and Docker's own chains; `ufw status` still reports "active" because
# it reads /etc/ufw/*.rules, not the kernel. Never use it here.
#
# Note the direction problem: this chain only sees FORWARD traffic (host<->container),
# never the host's own SSH in INPUT -- so a rule for port 22 here is pointless,
# UFW already covers that. And matching on destination port alone also catches
# the containers' own OUTBOUND traffic, so a blanket "DROP tcp/443" would cut
# Open WebUI off from Azure OpenAI. Inbound to a published port is DNAT'd to a
# Docker network address, so scoping by destination subnet is what separates
# "someone reaching us" from "us calling out".
cat > /usr/local/sbin/apply-docker-user-rules.sh <<EOF
#!/bin/sh
# Managed by scripts/10-harden.sh -- phase 10
set -e
ALLOWED_CIDRS='${ALLOWED_CIDRS}'

# Subnets of the local Docker networks; inbound to a published port is
# DNAT'd into one of these. Resolved at run time because Compose may pick a
# different subnet on a rebuild.
SUBNETS=\$(docker network ls -q | xargs -r docker network inspect \\
  --format '{{range .IPAM.Config}}{{.Subnet}} {{end}}' 2>/dev/null || true)
[ -n "\$SUBNETS" ] || SUBNETS='172.16.0.0/12'

iptables -N DOCKER-USER 2>/dev/null || true
iptables -F DOCKER-USER
for net in \$SUBNETS; do
  for c in \$ALLOWED_CIDRS; do
    iptables -A DOCKER-USER -d "\$net" -p tcp --dport 443 -s "\$c" -j RETURN
  done
  iptables -A DOCKER-USER -d "\$net" -p tcp --dport 443 -j DROP
  iptables -A DOCKER-USER -d "\$net" -p tcp --dport 80 -j DROP
done
# Everything else -- container egress, inter-container, DNS -- is untouched.
iptables -A DOCKER-USER -j RETURN

# Docker must traverse this chain, ahead of the FORWARD path that permits
# traffic. "(N references)" in the chain listing must be 1 or more.
iptables -C FORWARD -j DOCKER-USER 2>/dev/null || iptables -I FORWARD 1 -j DOCKER-USER
EOF
chmod 755 /usr/local/sbin/apply-docker-user-rules.sh

if /usr/local/sbin/apply-docker-user-rules.sh; then
  # UFW rewrites the ruleset on reload and a docker restart recreates the
  # DOCKER chain, so re-apply from a unit that runs after both.
  cat > /etc/systemd/system/ufw-docker-user.service <<'EOF'
[Unit]
Description=Re-apply the Docker allowlist rules after UFW or Docker rewrites them
After=ufw.service docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/apply-docker-user-rules.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now ufw-docker-user.service
  echo "OK: DOCKER-USER allowlist rules applied (443 from ${ALLOWED_CIDRS})."
else
  echo "ERROR: could not apply DOCKER-USER rules; 443 would rely on the NSG alone." >&2
fi

# The firewall is only real if the kernel agrees. UFW's own status output is
# not evidence -- verify the live INPUT policy, which is what the kernel uses.
if [ "$(iptables -L INPUT -n | head -1 | grep -o 'policy [A-Z]*' | awk '{print $2}')" != "DROP" ]; then
  echo "ERROR: kernel INPUT policy is not DROP -- the host firewall is not enforcing." >&2
 exit 1
fi
echo "OK: kernel INPUT policy is DROP (firewall actually enforcing)."

# -------------------------------------------------- 3. unattended upgrades --
# Security patches land without anyone remembering to run apt upgrade.
# Origins are already set to the archive pocket plus -security in
# /etc/apt/apt.conf.d/50unattended-upgrades; only the timers are pinned here.
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null
echo "OK: unattended security upgrades scheduled."

# ------------------------------------------------------------ 4. fail2ban --
# sshd already refuses passwords, so fail2ban is a second layer: it bans a
# source that hammers the service regardless of which credential it tries.
# The allowlist is in ignoreip so a real admin can never ban themselves out.
#
# journalmatch must name the unit that actually exists. On Ubuntu 24.04 that
# is ssh.service; there is no sshd.service. With the wrong name the jail
# starts, reports itself healthy, and silently matches nothing -- fail2ban
# then looks configured while banning nobody. Detect the real name instead
# of hard-coding either one.
if ! command -v fail2ban-client >/dev/null 2>&1; then
  # fail2ban is not part of the base image, so install it here rather than
  # assuming a previous manual step: on a fresh VM this script used to abort
  # partway with "No such file or directory" and silently skip the steps below.
  echo "    fail2ban not installed, installing it now"
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq fail2ban
fi

SSH_UNIT=$(systemctl list-units --all 'ssh.service' 'sshd.service' --no-legend --plain 2>/dev/null \
  | awk '{print $1}' | grep -E '^sshd?\.service$' | head -1)
[ -n "$SSH_UNIT" ] || SSH_UNIT=ssh.service
echo "    fail2ban will watch journal unit: ${SSH_UNIT}"
cat > /etc/fail2ban/jail.d/sshd-hardening.local <<EOF
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 3
# Never ban the office/home IP that terraform put in allowed_cidrs.
ignoreip = 127.0.0.1/8 ::1 ${ALLOWED_CIDRS}

[sshd]
enabled  = true
port     = 22
backend  = systemd
maxretry = 3
findtime = 10m
bantime  = 1h
journalmatch = _SYSTEMD_UNIT=${SSH_UNIT} + _COMM=sshd
EOF
systemctl enable --now fail2ban >/dev/null
sleep 3
systemctl reload fail2ban >/dev/null || systemctl restart fail2ban

# A jail that matches nothing looks exactly like a healthy jail in
# `fail2ban-client status`. Only the journal match count proves otherwise,
# so read it from the running service rather than trusting the file.
if [ "$(journalctl _SYSTEMD_UNIT="${SSH_UNIT}" --no-pager 2>/dev/null | wc -l)" -gt 0 ]; then
  echo "OK: fail2ban jail 'sshd' watching ${SSH_UNIT} (maxretry 3, bantime 1h)."
else
  echo "ERROR: journal unit ${SSH_UNIT} has no entries; the jail would never match." >&2
fi

# --------------------------------------------------- 5. docker log rotation --
# Without this, container logs grow until the data disk fills -- which would
# take Open WebUI's database down with it.
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
systemctl restart docker

# `systemctl restart docker` above rewrites the ruleset, which drops the
# DOCKER-USER entries. Re-apply so a plain docker restart cannot silently
# reopen 443 to the whole internet.
systemctl restart ufw-docker-user.service
echo "OK: DOCKER-USER allowlist re-applied after docker restart."
echo "OK: Docker log rotation set (10m x 3). Existing containers need a recreate."

# ---------------------------------------------------------- 6. env perms --
# .env holds the Azure OpenAI key. It must not be readable by other users.
for f in /home/*/app/docker/.env; do
  [ -e "$f" ] || continue
  chown "$(stat -c '%U' "$f")":"$(stat -c '%G' "$f")" "$f"
  chmod 600 "$f"
  echo "OK: $(stat -c '%a %U:%G' "$f")"
done

echo
echo "== Host hardening applied =="
echo "Remaining: container recreate to pick up log rotation (docker compose up -d --force-recreate)."
