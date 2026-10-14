# Operations

Day-two runbook. Every command here was run against the live environment.

## First thing: is it healthy?

```bash
ssh -i ~/.ssh/openwebui azureuser@<public_ip>
bash scripts/11-validate.sh
```

26 checks across services, containers, application, authentication, firewall,
disk, and secrets. Exits non-zero on any failure. Expected tail:

```
== Result: 26 passed, 0 failed ==
```

Narrower checks:

```bash
bash scripts/03-validate.sh       # containers + HTTPS only
bash scripts/04-access-check.sh   # access control (phase 9 invariants)
```

From your own machine:

```bash
curl -sk -o /dev/null -w '%{http_code}\n' https://<public_ip>   # 200
curl -s --max-time 5 http://<public_ip>:8080/ ; echo $?         # 28 = blocked
```

## Restarting

```bash
bash scripts/11-restart.sh            # application only
bash scripts/11-restart.sh --hard     # also restarts docker and reloads sshd
```

It stops the stack, starts the backend **before** the proxy (the other order
produces a window of 502s), waits for the container health check, then verifies
HTTPS and the backend through the proxy. If the backend will not come up it
stops Caddy and exits non-zero, so a failure is visible instead of serving 502s.

## The VM is shut down at 22:00 (UTC+3)

The nightly shutdown schedule keeps costs down. To use the platform out of
hours, start it manually:

```bash
az vm start -g rg-openwebui -n vm-openwebui
```

Wait for `az vm get-instance-view` to report `PowerState/running`, then connect.
To disable the schedule permanently:

```hcl
# terraform.tfvars
enable_auto_shutdown = false
```

```bash
cd terraform && terraform apply
```

## Backups

```bash
bash scripts/backup.sh              # create
bash scripts/backup.sh --list       # list
bash scripts/backup.sh --restore <archive>
```

A backup stops `open-webui` so the SQLite database is consistent, archives
`/mnt/data/open-webui` to `/mnt/data/backups`, and restarts it. The last 7
archives are kept.

Archives are ~800 MB because they include the embedding-model cache. To move a
backup off the VM, copy it somewhere outside the resource group — the data disk
is destroyed with `terraform destroy`.

## Logs

```bash
docker compose -f docker/docker-compose.yml logs -f open-webui
docker compose -f docker/docker-compose.yml logs -f caddy

sudo journalctl -u ssh -f
sudo fail2ban-client status sshd
df -h /mnt/data
```

Rotation is configured at the daemon level (10 MB × 3 files per container), so
logs cannot fill the data disk. Check it with:

```bash
docker inspect -f '{{.HostConfig.LogConfig.Config}}' docker-open-webui-1
# map[max-file:3 max-size:10m]
```

## Monitoring

| Resource | Purpose |
|---|---|
| `law-openwebui` | Log Analytics workspace, 30-day retention, 0.5 GB/day cap |
| `diag-openwebui` | VM diagnostic settings, `AllMetrics` → workspace |
| `ag-openwebui` | Action group, emails `faris@alfaifi.co` |
| `alert-vm-cpu` | Percentage CPU > 80% for 15 min |
| `alert-vm-memlow` | Available memory < 256 MB for 10 min |
| `alert-vm-diskread` | Disk Read Bytes (Total) > 2 MiB/s for 15 min |
| `alert-vm-netin` | Network In (Total) > 5 MiB/s for 15 min |

### Recreating them

They are **not** managed by Terraform. If the resource group is destroyed, these
are lost and must be recreated:

```bash
# Workspace with a spend cap
az monitor log-analytics workspace create \
  -g rg-openwebui -n law-openwebui -l centralus --retention-time 30

az resource update \
  --ids $(az monitor log-analytics workspace show -g rg-openwebui -n law-openwebui --query id -o tsv) \
  --set properties.workspaceCapping.dailyQuotaGB=0.5 \
  --set properties.workspaceCapping.dataIngestionStatus=RespectQuota

# Data collection endpoint
az monitor data-collection endpoint create \
  -g rg-openwebui -l centralus --data-collection-endpoint-name dce-openwebui \
  --public-network-access Enabled

# Action group (must be location "global")
az cognitiveservices account keys list -g rg-openwebui -n openwebui-aoai >/dev/null  # sanity
```

`az monitor action-group create` fails on Windows for `--email-receivers`; the
action group and alert rules are easiest to create through the ARM API.

### Checking alerts are alive

`conditionTime` in `az monitor metrics alert show` often reads `null`; that is
not proof of a problem. The status subresource is authoritative:

```bash
az monitor metrics alert list -g rg-openwebui \
  --query "[].{name:name,enabled:enabled,metric:criteria.allOf[0].metricName}" -o table
```

A rule is genuinely working when its `/status` subresource reports `Healthy`
with a recent timestamp. `Unhealthy` usually means the metric has no data —
check the metric name against:

```bash
az monitor metrics list-definitions \
  --resource <vm-resource-id> \
  --query "[].name.value" -o tsv
```

Two rules were originally created with wrong metric names (`Network In Total`,
`Disk Read Bytes` without an aggregation) and silently evaluated nothing.

## Costs

| Lever | Setting |
|---|---|
| Auto-shutdown | 22:00 UTC+3, `enable_auto_shutdown` |
| Log Analytics ingestion | hard cap 0.5 GB/day |
| VM size | `Standard_D2s_v7` (2 vCPU / 8 GB) |
| Budget alert | `openwebui-budget`, $100 |

```bash
az consumption budget list
```

## Routine review

```bash
# Anyone waiting for approval?
sudo docker exec docker-open-webui-1 python3 -c "
import sqlite3
c=sqlite3.connect('/app/backend/data/webui.db')
print([r for r in c.execute('select email,role from user')])"

# Is the admin still the only admin?
sudo docker exec docker-open-webui-1 python3 -c "
import sqlite3
c=sqlite3.connect('/app/backend/data/webui.db')
print([r for r in c.execute(\"select email,role from user where role='admin'\")])"
```

## Rotating the Azure OpenAI key

```bash
az cognitiveservices account regenerate-key -g rg-openwebui -n openwebui-aoai --key-name key1

# Update on the VM, then restart so the container picks it up
ssh -i ~/.ssh/openwebui azureuser@<public_ip>
sed -i 's/^OPENAI_API_KEY=.*/OPENAI_API_KEY=<new key>/' docker/.env
bash scripts/11-restart.sh
```

The key is also cached inside the Open WebUI database. Update it there too, or
reconfigure the connection in the admin panel, otherwise the old key stays in
use.