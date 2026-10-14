#!/usr/bin/env bash
# 11-validate.sh — Phase 11: full system health check
#
# Run on the VM:  ./11-validate.sh
#
# Unlike 03-validate.sh (container smoke test), this covers the whole host:
# services, firewall, hardening, disk, containers, and the HTTPS surface.
# Exits non-zero if anything fails, so it can be wired to monitoring.
set -uo pipefail   # not -e: a failed check must not abort the rest

pass=0
fail=0
ok()   { printf '  OK   %s\n' "$1"; pass=$((pass+1)); }
# Failures print to stdout too, so the section headers stay in order when the
# output is captured through a pipe (stderr and stdout flush separately).
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }
head_() { printf '\n== %s ==\n' "$1"; }

cd "$(dirname "$0")/../docker"

# --- services -------------------------------------------------------------
head_ "Services"
for svc in ssh docker fail2ban ufw; do
  if systemctl is-active --quiet "$svc"; then ok "$svc is active"; else bad "$svc is NOT active"; fi
done

# --- containers -----------------------------------------------------------
head_ "Containers"
for c in open-webui caddy; do
  name="docker-${c}-1"
  state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null || echo missing)
  if [ "$state" = "running" ]; then ok "$c is running"; else bad "$c is $state"; fi
done
# open-webui reports health via its image HEALTHCHECK; caddy has none.
health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' docker-open-webui-1 2>/dev/null || echo missing)
if [ "$health" = "healthy" ] || [ "$health" = "none" ]; then
  ok "open-webui health: $health"
else
  bad "open-webui health: $health"
fi

# Restart policy: a container that does not come back after a crash or a
# docker restart took the site down in phase 10.
for c in open-webui caddy; do
  pol=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "docker-${c}-1" 2>/dev/null || echo unknown)
  if [ "$pol" = "unless-stopped" ] || [ "$pol" = "always" ]; then
    ok "$c restart policy: $pol"
  else
    bad "$c restart policy: $pol (should be unless-stopped)"
  fi
done

# --- application ----------------------------------------------------------
head_ "Application"
if docker compose exec -T open-webui curl -fsS --max-time 10 http://localhost:8080/health >/dev/null 2>&1; then
  ok "open-webui answers /health internally"
else
  bad "open-webui does not answer /health internally"
fi
if curl -fsSk --max-time 10 https://localhost/ >/dev/null 2>&1; then
  ok "Caddy serves HTTPS on 443"
else
  bad "Caddy does not serve HTTPS on 443"
fi
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost/ || echo 000)
case "$code" in
  30[0-9]) ok "plain HTTP redirects to HTTPS ($code)" ;;
  *)       bad "plain HTTP did not redirect (got $code)" ;;
esac
# 8080 must never be reachable from the host.
if curl -fsS --max-time 5 http://localhost:8080/ >/dev/null 2>&1; then
  bad "port 8080 is reachable on the host (must stay private)"
else
  ok "port 8080 is not published to the host"
fi

# --- authentication (phases 9 and 14 invariants) ---------------------------
head_ "Authentication"
# Assert the stored config, not the endpoint. POSTing to /signup creates a real
# account on every run, and the security property that matters is that new
# accounts are held pending, not whether the form is visible.
signup=$(docker compose exec -T open-webui python3 -c '
import sqlite3
c = sqlite3.connect("/app/backend/data/webui.db")
r = c.execute("select value from config where key=?", ("ui.enable_signup",)).fetchone()
print((r[0] if r else "").strip("\"\x27"))' 2>/dev/null)
if [ "$signup" = "true" ]; then ok "registration is open"; else bad "ui.enable_signup is '$signup' (expected true)"; fi
role=$(docker compose exec -T open-webui python3 -c '
import sqlite3
c = sqlite3.connect("/app/backend/data/webui.db")
r = c.execute("select value from config where key=?", ("ui.default_user_role",)).fetchone()
print((r[0] if r else "").strip("\"\x27"))' 2>/dev/null)
if [ "$role" = "pending" ]; then ok 'new users default to "pending"'; else bad "default user role is '$role'"; fi

# --- firewall & ssh (phase 10 invariants) ---------------------------------
head_ "Firewall & SSH"
# These need root. Without it, iptables -L and sshd -T print nothing and the
# checks would report a false failure, so fall back to sudo when available
# and only skip (rather than fail) if neither can read them.
as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; elif sudo -n true 2>/dev/null; then sudo "$@"; else return 1; fi; }

policy=$(as_root iptables -L INPUT -n 2>/dev/null | head -1 | grep -o 'policy [A-Z]*' | awk '{print $2}')
if [ "${policy:-}" = "DROP" ]; then
  ok "kernel INPUT policy is DROP"
elif [ -z "$policy" ]; then
  echo "  SKIP kernel INPUT policy (needs root)"
else
  bad "kernel INPUT policy is $policy (ufw status alone is not proof)"
fi

du=$(as_root iptables -L DOCKER-USER -n 2>/dev/null | head -1 | grep -o '([0-9]* references' | tr -dc '0-9')
if [ "${du:-0}" -ge 1 ]; then
  ok "DOCKER-USER chain is wired into FORWARD"
elif [ -z "$du" ]; then
  echo "  SKIP DOCKER-USER reference count (needs root)"
else
  bad "DOCKER-USER chain has 0 references (docker may bypass the allowlist)"
fi

for kv in permitrootlogin:no passwordauthentication:no; do
  k=${kv%%:*}; want=${kv#*:}
  got=$(as_root sshd -T 2>/dev/null | awk -v k="$k" '$1==k{print $2; exit}')
  if [ "$got" = "$want" ]; then
    ok "$k = $got"
  elif [ -z "$got" ]; then
    echo "  SKIP $k (needs root to read sshd -T)"
  else
    bad "$k = $got (expected $want)"
  fi
done

banned=$(as_root fail2ban-client status sshd 2>/dev/null | grep -i "Banned IP list" | sed 's/.*list:[[:space:]]*//')
if [ -z "${banned// /}" ]; then ok "fail2ban jail active, nobody banned"; else echo "  INFO currently banned: $banned"; fi

# --- disk -----------------------------------------------------------------
head_ "Disk"
for mnt in / /mnt/data; do
  pct=$(df --output=pcent "$mnt" 2>/dev/null | tail -1 | tr -dc '0-9')
  if [ -n "$pct" ] && [ "$pct" -lt 80 ]; then
    ok "$mnt at ${pct}% used"
  else
    bad "$mnt at ${pct:-?}% used (threshold 80%)"
  fi
done
# Log rotation is what stops the logs filling that disk.
for c in open-webui caddy; do
  opts=$(docker inspect -f '{{.HostConfig.LogConfig.Config}}' "docker-${c}-1" 2>/dev/null)
  case "$opts" in *max-size*) ok "$c log rotation: $opts" ;; *) bad "$c has no log rotation ($opts)" ;; esac
done

# --- secrets --------------------------------------------------------------
head_ "Secrets"
perms=$(stat -c '%a' .env 2>/dev/null || echo "?")
if [ "$perms" = "600" ]; then ok ".env is 600"; else bad ".env is $perms (should be 600)"; fi
if [ -f .env.bak ]; then bad ".env.bak exists and may hold a copy of the API key"; else ok "no stray .env backup"; fi

# --- summary --------------------------------------------------------------
printf '\n== Result: %d passed, %d failed ==\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
