#!/usr/bin/env bash
# 04-access-check.sh — Phase 9: secure access & authentication
#
# Run ON THE VM (part of the access-control surface). It proves:
#   1. TLS is terminated on 443 and the app answers over HTTPS
#   2. plain HTTP is redirected to HTTPS
#   3. port 8080 is NOT published on the host (private to the docker network)
#   4. registration is open and new accounts are held pending approval
#   5. new accounts default to the "pending" role and are locked out
#   6. the session cookie is Secure + SameSite=strict
#
# The NSG half (a non-allowlisted IP cannot reach 22/443) can only be judged
# from Azure, so it is checked separately -- see the note printed at the end.
set -euo pipefail

cd "$(dirname "$0")/../docker"

fail=0
ok()   { echo "OK:   $1"; }
bad()  { echo "FAIL: $1" >&2; fail=1; }

# --- 1. HTTPS on 443 -------------------------------------------------------
if curl -fsSk https://localhost/ >/dev/null; then
  ok "Caddy is serving HTTPS on 443."
else
  bad "No HTTPS response on 443. Check: docker compose logs caddy"
fi

# The certificate must cover the address users actually type. A browser
# warning is expected (internal CA); a mismatch on the IP is not.
site=$(grep -E '^SITE_ADDRESS=' .env | cut -d= -f2-)
if [ -n "${site:-}" ]; then
  san=$(echo | openssl s_client -connect "localhost:443" 2>/dev/null \
        | openssl x509 -noout -ext subjectAltName 2>/dev/null || true)
  if printf '%s' "$san" | grep -q "IP Address:${site}"; then
    ok "Certificate covers SITE_ADDRESS (${site})."
  else
    bad "Certificate does not cover ${site}. Found: ${san:-<none>}"
  fi
else
  bad "SITE_ADDRESS is missing from .env -- Caddy has no address to issue for."
fi

# --- 2. HTTP -> HTTPS ------------------------------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://localhost/ || echo 000)
case "$code" in
  30[0-9]) ok "Plain HTTP redirects to HTTPS (${code})." ;;
  *)       bad "Plain HTTP did not redirect to HTTPS (got ${code})." ;;
esac

# --- 3. 8080 stays private -------------------------------------------------
# open-webui must use `expose`, never `ports`: nothing may bind 8080 on the host.
if docker compose config | grep -qE '^\s+published:\s*"?8080'; then
  bad "open-webui publishes 8080 to the host. It must use 'expose' only."
else
  ok "open-webui publishes no host port."
fi

if curl -fsS --max-time 5 http://localhost:8080/ >/dev/null 2>&1; then
  bad "Something is listening on host port 8080."
else
  ok "Nothing listens on host port 8080."
fi

# --- 4. registration is open but lands in pending --------------------------
# The config is asserted rather than the endpoint: POSTing to /signup would
# create a real account on every run, and the meaningful question is not
# "is signup allowed" but "does a new account get access by default".
cfg=$(docker compose exec -T open-webui python3 -c '
import sqlite3
c = sqlite3.connect("/app/backend/data/webui.db")
v = c.execute("select value from config where key=?", ("ui.enable_signup",)).fetchone()
print((v[0] if v else "").strip("\"\x27"))
')
if [ "$cfg" = "true" ]; then
  ok "Registration is open (sign-up enabled)."
else
  bad "ui.enable_signup is '${cfg:-unset}'. Expected true so users can request access."
fi

# --- 5. new accounts start as pending --------------------------------------
role=$(docker compose exec -T open-webui python3 -c '
import sqlite3
c = sqlite3.connect("/app/backend/data/webui.db")
r = c.execute("select value from config where key=?", ("ui.default_user_role",)).fetchone()
print((r[0] if r else "").strip("\"'"'"'"))
')
if [ "$role" = "pending" ]; then
  ok 'New accounts default to role "pending".'
else
  bad "ui.default_user_role is '${role}', expected pending."
fi

# --- 6. session cookie hardening ------------------------------------------
for pair in 'WEBUI_SESSION_COOKIE_SECURE:true' 'WEBUI_SESSION_COOKIE_SAME_SITE:strict'; do
  var=${pair%%:*}; want=${pair#*:}
  got=$(docker inspect docker-open-webui-1 \
        --format "{{range .Config.Env}}{{println .}}{{end}}" | sed -n "s/^${var}=//p")
  if [ "$got" = "$want" ]; then
    ok "${var}=${got}"
  else
    bad "${var} is '${got}', expected '${want}'."
  fi
done

# The gate only works if the running config agrees with the environment.
signup=$(docker compose exec -T open-webui python3 -c '
import sqlite3
c = sqlite3.connect("/app/backend/data/webui.db")
r = c.execute("select value from config where key=?", ("ui.enable_signup",)).fetchone()
print((r[0] if r else "").strip("\"\x27"))
')
if [ "$signup" = "true" ]; then
  ok "Running config has sign-up enabled (Admin Panel value, which overrides the env var)."
else
  bad "Running config has ui.enable_signup=${signup:-unset}. Expected true."
fi

echo
echo "== NSG half (must be run from a machine with the Azure CLI) =="
cat <<'EOF'
  # Deny proof, using a source IP that is NOT in allowed_cidrs:
  az network watcher test-ip-flow -g rg-openwebui -n vm-openwebui \
    --direction Inbound --protocol TCP \
    --local <vm-private-ip>:443 --remote 203.0.113.77:51000 \
    --query "{verdict:access,rule:ruleName}" -o tsv      # expect Deny

  # Allow proof, using an allowlisted IP:
  az network watcher test-ip-flow -g rg-openwebui -n vm-openwebui \
    --direction Inbound --protocol TCP \
    --local <vm-private-ip>:443 --remote <your-ip>:51000 \
    --query "{verdict:access,rule:ruleName}" -o tsv      # expect Allow

  # <vm-private-ip> is the NIC address (az network nic show ... privateIPAddress),
  # not the public IP -- the watcher rejects a local address that is not on the NIC.
EOF

[ "$fail" -eq 0 ] || exit 1
echo
echo "== All access checks passed =="