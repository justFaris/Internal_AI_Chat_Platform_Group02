# Troubleshooting

Real failures encountered while building this, and how to diagnose them.

## Start here

```bash
bash scripts/11-validate.sh
```

It names the failing layer. Then use the sections below.

| Symptom | Go to |
|---|---|
| `https://<ip>` shows 502 | [Caddy cannot reach the backend](#502-bad-gateway) |
| Site is unreachable at all | [Connection times out](#site-unreachable) |
| Nothing listens on 443 | [Caddy is down](#443-not-listening) |
| Cannot SSH in | [SSH broken](#cannot-ssh-in) |
| App hangs at startup, 502 for minutes | [Backend blocked at startup](#backend-hangs-at-startup) |
| Login fails with a valid password | [Auth issues](#authentication-problems) |
| `terraform destroy` stops halfway | [Destroy is blocked](#terraform-destroy-stops-partway) |
| Azure OpenAI key rejected | [Key problems](#azure-openai-key-problems) |
| An alert shows `Unhealthy` | [Alert evaluation](#alerts-report-unhealthy) |

---

## 502 Bad Gateway

Caddy is up but cannot reach `open-webui:8080`.

```bash
docker compose -f docker/docker-compose.yml ps
docker compose -f docker/docker-compose.yml logs --tail 50 caddy open-webui
docker inspect -f '{{.State.Health.Status}}' docker-open-webui-1
```

Most common cause is ordering: the backend is still booting. `11-restart.sh`
starts the backend first and waits for it to be healthy for exactly this reason.

If the backend never becomes healthy:

```bash
docker compose -f docker/docker-compose.yml logs --tail 50 open-webui
df -h /mnt/data          # a full data disk stops SQLite
```

---

## Site unreachable (connection times out)

Expected from any address that is **not** in `allowed_cidrs`. Confirm before
assuming a fault:

```bash
curl -s https://api.ipify.org                      # your address right now
grep allowed_cidrs terraform/terraform.tfvars      # is it listed?
```

If your own address has changed — which a dynamic ISP address does routinely —
add it to `allowed_cidrs` and apply:

```bash
cd terraform && terraform apply
```

> **Changing `terraform.tfvars` alone will not let you back in.** The NSG is
> only the outer layer; the VM's own firewall (`ufw` plus the `DOCKER-USER`
> chain) keeps its own copy of the allow-list and will still refuse you. Once
> you are back in, re-apply it so the two layers do not drift:
>
> ```bash
> sudo bash scripts/10-harden.sh <your-ip>/32 [<other-ip>/32 ...]
> ```
>
> If you are already locked out of SSH, run that same script through
> `az vm run-command`, which executes via the Azure guest agent and is
> therefore not subject to either firewall:
>
> ```bash
> az vm run-command -g rg-openwebui -n vm-openwebui \
>   --command-id RunShellScript \
>   --scripts "sudo bash /home/azureuser/app/scripts/10-harden.sh <your-ip>/32"
> ```
>
> Pass several addresses by quoting the whole argument list, which is also
> worth doing whenever your address might change again.

The VM shuts down nightly at 22:00 (UTC+3). If it is gone:

```bash
az vm get-instance-view -g rg-openwebui -n vm-openwebui \
  --query "instanceView.statuses[1].{code:code,display:displayStatus}" -o tsv
az vm start -g rg-openwebui -n vm-openwebui
```

---

## 443 not listening

```bash
docker ps -a --format "{{.Names}}\t{{.Status}}"
docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' docker-caddy-1
```

A container that is `Exited (0)` with restart policy `no` will not come back by
itself. That exact state appeared during setup: `restart: unless-stopped` had
been lost for Caddy, so every `docker restart` left the site down permanently.
`11-validate.sh` now checks both restart policies.

```bash
cd docker && docker compose up -d --force-recreate
```

---

## Cannot SSH in

```bash
ssh -vvv -i ~/.ssh/openwebui azureuser@<public_ip>
```

| Message | Meaning |
|---|---|
| `Permission denied (publickey)` | Key rejected, or `authorized_keys` missing on the VM |
| `Connection timed out` | Your IP is not in `allowed_cidrs`, or the VM is stopped |
| `Connection refused` | sshd is not running |

Password login is **supposed** to fail. If you need to confirm it is disabled
rather than broken:

```bash
ssh -o PreferredAuthentications=password -o PubkeyAuthentication=no \
    -o NumberOfPasswordPrompts=1 azureuser@<public_ip>
# expect: Permission denied (publickey)
```

If you have lost the private key, you cannot log in by design — use Azure
serial console or reset the user credentials, then re-inject the public key
through Terraform.

---

## Backend hangs at startup

Symptom: `open-webui` is running but never becomes healthy, and Caddy serves
502. Logs stop after `Waiting for application startup`.

Check egress from inside the container:

```bash
docker exec open-webui curl -s -o /dev/null -w '%{http_code}\n' \
  --max-time 15 https://huggingface.co
docker exec open-webui curl -s -o /dev/null -w '%{http_code}\n' \
  --max-time 15 https://openwebui-aoai.openai.azure.com
```

Both should return an HTTP code. A timeout means the container cannot reach the
internet.

This is almost always a firewall rule. `DOCKER-USER` rules that match only on
destination port block the containers' own outbound traffic as well as inbound
connections — which cuts Open WebUI off from the model API and produces exactly
this hang. Rules must be scoped by destination subnet so "someone reaching us"
stays separate from "us calling out".

```bash
sudo iptables -L DOCKER-USER -n --line-numbers
```

Apply the correct set:

```bash
sudo /usr/local/sbin/apply-docker-user-rules.sh
```

---

## Container logs are not rotating

```bash
docker inspect -f '{{.HostConfig.LogConfig.Config}}' docker-open-webui-1
```

Empty map means rotation is not configured. `/etc/docker/daemon.json` only
applies to containers created *after* the daemon restart, so existing containers
must be recreated:

```bash
cat /etc/docker/daemon.json
docker compose up -d --force-recreate
```

---

## Authentication problems

### Sign-up is still open

Open WebUI reads `ui.enable_signup` from its **database**, which overrides the
environment variable. Changing `docker-compose.yml` alone does nothing.

```bash
sudo docker exec docker-open-webui-1 python3 -c "
import sqlite3
c=sqlite3.connect('/app/backend/data/webui.db')
print(c.execute(\"select value from config where key='ui.enable_signup'\").fetchone())"
```

Change it in the admin panel, or in that table. `04-access-check.sh` asserts the
running value rather than the env var.

### Login rejected with the right password

```bash
sudo docker exec docker-open-webui-1 python3 -c "
import sqlite3
c=sqlite3.connect('/app/backend/data/webui.db')
print([r for r in c.execute('select email,role from user')])"
```

A role of `pending` means the account has not been approved; `pending` users
receive 401 on every API call, including model access.

### Session expires immediately

`WEBUI_SESSION_COOKIE_SECURE=true` means the cookie is only sent over HTTPS.
Accessing the app over plain HTTP (for example through a tunnel to port 80)
will not work. Use HTTPS, including through the tunnel:

```bash
ssh -i ~/.ssh/openwebui -L 8443:localhost:443 azureuser@<public_ip>
# then open https://localhost:8443
```

---

## Terraform destroy stops halfway

```
Error: ... resource_group ... please either remove these Resources, or disable
this behaviour using the feature flag `prevent_deletion_if_contains_resources`
```

The resource group is managed by Terraform but contains resources it does not
manage (Azure OpenAI, Log Analytics, the action group, alert rules). Azure
refuses to delete a non-empty group, so destroy deletes everything else and
stops — leaving a half-deleted environment.

`terraform/providers.tf` sets the flag to `false` so the group can be removed.
The real fix is to declare those resources in Terraform or move them to their
own resource group.

---

## Azure OpenAI key problems

### "An existing resource ... has been soft-deleted"

The account still exists in soft-delete state. Recreating under the same name
fails. Restore it — this preserves the original key and deployment:

```bash
# PUT the account body with "restore": true in properties
# (az cognitiveservices has no --restore flag; use the ARM API)
```

If it cannot be restored, purge it first and create a new account, which means
generating a new key and updating `.env`.

### Key rejected (401)

```bash
az cognitiveservices account keys list -g rg-openwebui -n openwebui-aoai
grep OPENAI_API_KEY docker/.env
curl -s -o /dev/null -w '%{http_code}\n' \
  https://openwebui-aoai.openai.azure.com/openai/v1/chat/completions \
  -H "api-key: <key>" -H "Content-Type: application/json" \
  -d '{"model":"gpt-5-mini","messages":[{"role":"user","content":"hi"}]}'
```

The key is cached in the Open WebUI database as well as in `.env`. Rotating one
without the other leaves the app using the old key.

---

## Alerts report Unhealthy

`Unhealthy` usually means the rule has **no data to evaluate**, which is
usually a wrong metric name or aggregation.

```bash
az monitor metrics list-definitions \
  --resource <vm-resource-id> --query "[].name.value" -o tsv
```

Two rules were created here with names that do not exist
(`Network In Total` instead of `Network In`) and silently evaluated nothing.
`conditionTime` reading `null` is normal and is not evidence of a fault; check
the status subresource instead:

```bash
az monitor metrics alert list -g rg-openwebui \
  --query "[].{name:name,metric:criteria.allOf[0].metricName}" -o table
```

---

## Firewall rules vanish after a Docker restart

```bash
sudo iptables -L DOCKER-USER -n | head -1
```

`Chain DOCKER-USER (0 references)` means Docker rebuilt its chains and the
allow-list is no longer in the path — 443 is effectively open to the internet,
protected only by the NSG. Re-apply:

```bash
sudo systemctl restart ufw-docker-user.service
```

`10-harden.sh` does this automatically after restarting Docker.

---

## Getting more information

```bash
sudo journalctl -u ssh -p err --since "10 minutes ago" --no-pager
sudo journalctl -u docker --since "10 minutes ago" --no-pager
docker compose -f docker/docker-compose.yml logs --tail 100
sudo fail2ban-client status sshd
df -h /mnt/data
```

If you are locked out of SSH, use the Azure serial console:
`az vm get-instance-view`, then the VM's **Serial console** blade in the portal.