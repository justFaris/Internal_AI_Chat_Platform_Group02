# Security

## Threat model

The asset is the Open WebUI database: chats, uploaded documents, and the admin
account. The realistic threats, in rough order of likelihood:

| Threat | Control |
|---|---|
| Someone on the internet reaches the app | NSG allow-list; only 22 and 443 are open, from `allowed_cidrs` |
| Password guessing or brute force | Password authentication is disabled entirely; SSH is key-only |
| Credential stuffing against the web login | Registration is open, but new accounts land as `pending` and can do nothing until an admin approves; the IP allow-list limits who can even reach the form |
| Traffic interception | TLS on 443; session cookies marked `Secure` and `SameSite=strict` |
| A compromised container reaching the host | Only Caddy can reach Open WebUI; port 8080 is not published |
| Secret leakage via git | `.env` is git-ignored and mode `600`; a secrets scan found no key in the repo or its history |
| Data loss | Managed data disk plus `backup.sh` |
| Cost runaway | Nightly shutdown, Log Analytics daily cap, $100 budget alert |

Explicitly **out of scope**: high availability, DDoS protection, and forensic
logging. This is a single-VM deployment with an IP allow-list in front of it.

## Layers

### 1. Network — NSG

Only two inbound rules exist; Azure's default `DenyAllInBound` covers the rest.

```
allow-ssh-from-allowlist   priority 100   TCP 22    from allowed_cidrs
allow-web-from-allowlist   priority 110   TCP 443   from allowed_cidrs
```

Port 80 is **not** allowed, so the plain-HTTP redirect is only reachable from
the VM itself and the SSH tunnel.

### 2. Host firewall — UFW plus `DOCKER-USER`

UFW mirrors the NSG: default-deny inbound, 22 and 443 from the allow-list only.

> **Docker bypasses UFW.** A published container port is DNAT'd in `PREROUTING`
> and then ACCEPTed by Docker's own chain, which runs before the `INPUT` chain
> UFW manages. `ufw allow 443` therefore has no effect on the published port.
> The fix is the `DOCKER-USER` chain, which runs ahead of it. Without this the
> NSG is the *only* thing protecting 443.

Rules are applied one at a time on purpose. `iptables-restore` without
`--noflush` replaces the entire filter table, silently destroying UFW's rules
and Docker's chains — and `ufw status` still reports "active" because it reads
its config files rather than the kernel. `10-harden.sh` verifies the live
`INPUT` policy is `DROP` rather than trusting that output.

Rules are scoped by **destination subnet**, not destination port alone. A
blanket "drop TCP 443" also drops the containers' own outbound calls to Azure
OpenAI, which hangs the backend at startup with a 502.

### 3. SSH

```
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
X11Forwarding no
AllowTcpForwarding yes      # required for the phase 6 tunnel
```

Verified: password login returns `Permission denied (publickey)`; root login is
refused.

### 4. Brute force — fail2ban

Jail on SSH with `maxretry 3`, `findtime 10m`, `bantime 1h`. The allow-list IP
is in `ignoreip` so an administrator cannot ban themselves out.

Two things that bit during setup, both silent:

- The journal must match the unit that exists. Ubuntu 24.04 uses `ssh.service`;
  there is no `sshd.service`. With the wrong name the jail starts, reports
  itself healthy, and matches nothing.
- fail2ban 1.0.2 on this image uses **nftables** (`table inet f2b-table`), not
  iptables. Looking for `f2b` chains in `iptables -L` finds nothing and looks
  like the ban is not enforced.

Verified with a real brute force from a temporary loopback address: 3 failures
→ 1 IP banned → that IP's SSH attempts rejected with
`Connection refused`, while the real admin IP stayed unbanned.

### 5. Application

| Setting | Value | Why |
|---|---|---|
| `ENABLE_SIGNUP` | `true` | Registration is open to anyone on an allow-listed IP |
| `DEFAULT_USER_ROLE` | `pending` | A new account can do nothing until an admin approves it — registration is open, *access* is not |
| `WEBUI_SESSION_COOKIE_SECURE` | `true` | Cookie never sent over cleartext |
| `WEBUI_SESSION_COOKIE_SAME_SITE` | `strict` | No cross-site session use |
| `CORS_ALLOW_ORIGIN` | the site's own origin | Stops other sites driving the API |

Verified on the wire: `set-cookie: ... HttpOnly; SameSite=strict; Secure`.

A pending user was tested end to end: signup produced `"role":"pending"`, and
that token received 401 on `/api/v1/models`, `/api/v1/users`, and
`/api/chat/completions`. Approving the account flipped the same token to 200.

> `ENABLE_SIGNUP` in `docker-compose.yml` is **not** authoritative. Open WebUI
> reads `ui.enable_signup` from its database, which the admin panel can change;
> that stored value wins. `04-access-check.sh` asserts the running config, not
> just the environment variable.

### 6. Secrets

- `docker/.env` holds the Azure OpenAI key and session secret: mode `600`,
  owned by the deploying user, git-ignored.
- `.env` is **not** in the repository. `env.example` documents the shape.
- A secrets scan of the working tree and full git history found the live key in
  zero places.
- Images are pinned to immutable digests, so `compose pull` cannot introduce a
  different build.

### 7. Container hardening

- **Log rotation** 10 MB × 3 per container, set in `/etc/docker/daemon.json`.
  Without it, logs grow until the data disk fills, taking the database with it.
- **Images pinned by digest**, not by tag.
- **`restart: unless-stopped`** on both services. This was lost for Caddy during
  an earlier edit, which meant any `docker restart` left the site permanently
  down with a 502. `11-validate.sh` checks the restart policy of both.

## Verification

```bash
bash scripts/11-validate.sh
```

Checks the kernel firewall policy, that `DOCKER-USER` is actually referenced,
root/password SSH settings, `.env` permissions, log rotation, disk headroom,
container restart policies, and that 8080 is not published.

Network denial is verified from Azure with a flow test:

```bash
az network watcher test-ip-flow \
  -g rg-openwebui --vm vm-openwebui \
  --direction Inbound --protocol TCP \
  --local <vm-private-ip>:443 --remote 203.0.113.77:51000 \
  --query "{verdict:access,rule:ruleName}" -o tsv
# expect: Deny   defaultSecurityRules/DenyAllInBound
```

Use the VM's **private** IP (`az network nic show ... privateIPAddress`); the
watcher rejects a local address that is not on the NIC.

## Known gaps

1. **No log centralisation.** VM metrics reach Log Analytics; container and
   syslog logs do not. Data Collection Rules were rejected by the API in this
   subscription on every version, and the VM exposes no diagnostic log
   categories. Logs live only on the VM.
2. **Alerts never fired.** Rules evaluate and report `Healthy`, but no alert was
   deliberately triggered, so email delivery is unproven.
3. **Internal CA certificate.** Browsers show a warning on first visit. Traffic
   is encrypted but not publicly trusted.
4. **Key rotation outstanding.** The Azure OpenAI key was exposed in a
   group-readable backup file and in terminal output before being removed.
5. **Single VM, no HA.** No load balancer, no zone redundancy.
6. **`auth.jwt_expiry` is 4 weeks**, and with no Redis configured, signing out
   does not revoke an already-issued token.
7. **No CI.** Nothing enforces the checks on every change.

## Reporting

Security issues in this project are handled as normal bugs: open an issue
describing the exposure and reproduction. Do not include real keys.