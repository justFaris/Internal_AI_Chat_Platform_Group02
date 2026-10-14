# Deployment

How to build this environment from nothing. Verified by a full
`terraform destroy` and rebuild; see [Reproducibility](#reproducibility).

## Prerequisites

| Tool | Version used |
|---|---|
| Azure CLI | logged in to the target subscription |
| Terraform | 1.6+ (azurerm provider 4.x) |
| SSH client | key-based auth only |
| An Azure OpenAI-capable subscription | `gpt-5-mini` in `centralus` |

You need your own public IP in the allow-list. Find it with `curl https://api.ipify.org`.

## 1. Configuration

```bash
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
subscription_id = "<your-subscription-id>"

# Your public IP plus any teammate IPs. Everything else is denied.
allowed_cidrs = ["203.0.113.10/32"]

# Path to the SSH *public* key that will be injected into the VM.
ssh_public_key_path = "~/.ssh/openwebui.pub"
```

Optional overrides: `project_name`, `location`, `vm_size`, `os_disk_size_gb`,
`data_disk_size_gb`, `enable_auto_shutdown`, `auto_shutdown_time`, `tags`.

`terraform.tfvars` is git-ignored — never commit it.

### Addresses are never written down

Two kinds of address change, and both are handled the same way: **look them up,
never copy them.**

| Address | Why it moves |
|---|---|
| The VM's public IP | Reallocated by Azure every time the resource group is destroyed and rebuilt |
| Your own public IP | Many ISPs hand out a dynamic address, which can change mid-session |

So no real address appears anywhere in this documentation. Examples use the
RFC 5737 documentation ranges (`203.0.113.0/24`, `192.0.2.0/24`), and every
command reads the current value at the moment it runs:

```bash
# The VM's address, straight from the deployment
terraform -chdir=terraform output -raw public_ip

# Your own address, to add to allowed_cidrs
curl -s https://api.ipify.org
```

`allowed_cidrs` should list every address that legitimately needs access —
yours, plus anyone else's who must reach the platform. Add them as you go and
remove addresses that are no longer used. Because an admin's own address can
change at any time, `scripts/10-harden.sh` accepts a **list** of CIDRs:

```bash
sudo bash scripts/10-harden.sh <first-ip>/32 <second-ip>/32
```

If you are locked out because your address changed, both the NSG *and* the host
firewall will refuse you. Recovery is described under "Site unreachable" in
[troubleshooting.md](troubleshooting.md).

### SSH key

```bash
ssh-keygen -t ed25519 -f ~/.ssh/openwebui -C "openwebui"
```

Keep the private key safe. Losing it means losing the VM: password
authentication is disabled by design.

## 2. Infrastructure

```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Apply prints the outputs you need:

```
public_ip        = "203.0.113.10"        # documentation example, not a real address
ssh_command      = "ssh -i ~/.ssh/openwebui azureuser@203.0.113.10"
data_disk_device = "/dev/disk/azure/data/by-lun/0"
```

This creates the resource group, VNet, subnet, NSG, static public IP, NIC, VM,
managed data disk, and the nightly shutdown schedule.

> **The resource group is a Terraform resource, but not everything inside it
> is.** The Azure OpenAI account, Log Analytics workspace, data collection
> endpoint, action group, and alert rules are created outside Terraform. See
> [step 5](#5-monitoring) and the warning in `terraform/providers.tf`.

## 3. Prepare the VM

Copy the application files to the VM:

```bash
scp -r docker scripts azureuser@<public_ip>:~/app/
ssh -i ~/.ssh/openwebui azureuser@<public_ip>
```

Then, on the VM:

```bash
cd ~/app
bash scripts/00-prepare.sh    # updates, UFW baseline, formats and mounts /mnt/data
bash scripts/01-install-docker.sh
```

`00-prepare.sh` is idempotent: it formats the data disk only if it is empty, so
re-running it on an existing VM will not destroy data.

Verify the mount:

```bash
df -h /mnt/data        # expect /dev/nvme1n2, 63G
```

## 4. Application

### `.env`

```bash
cp docker/.env.example docker/.env
chmod 600 docker/.env
```

Fill it in. **Do not copy an address from anywhere else in this document** —
take the current value from the Terraform output above, because the public IP is
reallocated on every destroy and rebuild:

```bash
# Read it rather than typing it, so a rebuild cannot leave a stale address:
VM_IP=$(cd ../terraform && terraform output -raw public_ip)

# The VM's public IP — Caddy issues its certificate for this address.
SITE_ADDRESS=${VM_IP}

# Browsers only. Add ;https://localhost if you also use the SSH tunnel.
CORS_ALLOW_ORIGIN=https://${VM_IP}

# Azure OpenAI
OPENAI_API_BASE_URL=https://openwebui-aoai.openai.azure.com/openai/v1
OPENAI_API_KEY=<key from: az cognitiveservices account keys list -g rg-openwebui -n openwebui-aoai>

# openssl rand -base64 32
WEBUI_SECRET_KEY=<generated>
```

`.env` must be mode `600` and is git-ignored.

### Deploy

```bash
bash scripts/02-deploy.sh
bash scripts/03-validate.sh
```

Open `https://<public_ip>` and accept the self-signed certificate warning. The
first account to register becomes the administrator; sign-up then closes
automatically, and `ENABLE_SIGNUP=false` keeps it closed.

## 5. Azure OpenAI (not in Terraform)

```bash
az cognitiveservices account create \
  -g rg-openwebui -n openwebui-aoai --kind OpenAI --sku S0 -l centralus

az cognitiveservices account deployment create \
  -g rg-openwebui -n openwebui-aoai -d gpt-5-mini \
  --model-name gpt-5-mini --model-version 2025-08-01 \
  --sku-name GlobalStandard
```

## 6. Monitoring (not in Terraform)

```bash
# Log Analytics, with a hard cap on spend
az monitor log-analytics workspace create \
  -g rg-openwebui -n law-openwebui -l centralus --retention-time 30
# then set workspaceCapping.dailyQuotaGB = 0.5 (see operations.md)

# VM metrics -> workspace
# Action group ag-openwebui -> faris@alfaifi.co
# Metric alert rules: alert-vm-cpu, alert-vm-memlow, alert-vm-diskread, alert-vm-netin
```

Exact commands are in [operations.md](operations.md#monitoring).

## 7. Harden

```bash
sudo bash scripts/10-harden.sh <your-ip>/32
docker compose -f docker/docker-compose.yml up -d --force-recreate
```

Pass your own CIDR. The script is idempotent, reloads sshd only after `sshd -t`
passes, and refuses to continue if no `authorized_keys` is present.

Then confirm:

```bash
bash scripts/11-validate.sh     # expect 26 passed, 0 failed
```

## Reproducibility

The environment was destroyed and rebuilt from this repository to prove it
works. Observations worth knowing before you repeat it:

- **`terraform destroy` is blocked by default.** The resource group contains
  resources Terraform does not manage, and Azure refuses to delete a non-empty
  group. `terraform/providers.tf` sets
  `prevent_deletion_if_contains_resources = false` so destroy can complete.
- **Azure OpenAI is soft-deleted, not destroyed.** Recreating under the same
  name fails; you must restore it, which preserves the key:
  put `"restore": true` in the account PUT body.
- **Everything outside Terraform is lost.** AOAI, monitoring, the data disk
  contents, and the admin account must be restored or recreated by hand.
- **The public IP changes** on rebuild. Update `SITE_ADDRESS` and
  `CORS_ALLOW_ORIGIN`, and re-add your client IP if `allowed_cidrs` drifted.

To rebuild an existing database after a destroy, copy `webui.db` back to
`/mnt/data/open-webui/` before starting the stack. That preserves the admin
account, chats, and settings.

## Teardown

```bash
# On the VM: stop the app but keep data
bash scripts/12-cleanup.sh

# From the machine with the repo: delete the Azure resources
bash scripts/12-cleanup.sh --terraform
```

`--terraform` deletes the resource group and therefore the Azure OpenAI account,
model deployment, and all monitoring as well. It asks for confirmation and
prints that warning first.

## Scripts reference

| Script | Runs on | Purpose |
|---|---|---|
| `00-prepare.sh` | VM | OS updates, UFW baseline, format + mount the data disk |
| `01-install-docker.sh` | VM | Docker Engine and Compose plugin |
| `02-deploy.sh` | VM | Pull images and `compose up -d` |
| `03-validate.sh` | VM | Container and HTTPS smoke test |
| `04-access-check.sh` | VM | Phase 9 access control checks |
| `backup.sh` | VM | Back up / restore `/mnt/data/open-webui` |
| `10-harden.sh` | VM | SSH, UFW, fail2ban, log rotation, image pinning checks |
| `11-validate.sh` | VM | Full system health check (26 checks) |
| `11-restart.sh` | VM | Ordered restart with verification |
| `12-cleanup.sh` | VM / machine | App teardown; `--terraform` for Azure resources |
| `99-cleanup.sh` | VM | Legacy minimal teardown |