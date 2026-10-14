# Internal AI Chat Platform (Based on Open WebUI)

**Project #10 · CC-RCP-10 · Team: CC-RCP-10-Team-2**

A self-hosted [Open WebUI](https://github.com/open-webui/open-webui) environment on Microsoft Azure that gives internal teams one controlled place to chat with AI models, summarise documents, and retrieve knowledge. Infrastructure is provisioned with Terraform, the host is prepared and operated with Bash automation, and Open WebUI runs as a Docker Compose stack backed by Azure OpenAI.

---

## Team

| Member | Part | Responsibility |
|---|---|---|
| Faris Al-Faifi | 1 — Infrastructure | Terraform for the resource group, VNet, subnet, NSG, static IP, VM, and persistent data disk |
| Norah Aljohani | 2 — VM Provisioning & Automation | Bash runbooks for host preparation, Docker Engine, mount handling, restarts, and backup |
| Saud Saad | 3 — Open WebUI + AI Backend Integration | Compose stack, Caddy reverse proxy, Azure OpenAI model deployment, and application configuration |
| Abeer Almehmadi | 4 — Security, Testing & Documentation | Host hardening, monitoring and alerting, acceptance testing, and the documentation set |

The four parts map directly onto the four directories in the repository, so ownership of an area is ownership of a folder.

---

## Problem

Without an internal AI platform, employees reach for public AI services. That creates three problems at once:

- Sensitive company material is pasted into third-party systems with no governance
- There is no shared, consistent way to use AI across engineering, operations, and support
- Knowledge stays in individual accounts instead of being usable by the team

The platform must provide:

- A single internal interface for AI assistance that the organisation controls
- Access control that an administrator can actually enforce
- A deployment that can be rebuilt from source, not one that only exists on one VM

---

## Scope

**In scope**

- Azure infrastructure provisioning with Terraform
- VM hosting Open WebUI, with a managed data disk for persistence
- Docker Compose deployment of Open WebUI behind a Caddy HTTPS reverse proxy
- Azure OpenAI model deployment and integration
- Bash automation for provisioning, validation, restart, backup, and teardown
- Host hardening, monitoring, alerting, and operational documentation

**Out of scope (version one)**

- Identity federation (SSO / OIDC / LDAP)
- Multi-tenant architecture and high availability
- Model hosting on the VM — inference is delegated to Azure OpenAI
- Centralised log analytics (see *Known limitations*)

---

## Architecture

```
Internal users (allow-listed address only)
        │
        │  HTTPS 443
        ▼
┌─────────────── Azure · resource group ─────────────────────────────┐
│  VNet + Subnet · NSG (allow 22 + 443 from the allow-list only)     │
│                                                                    │
│   ┌──────── Azure VM (Ubuntu 24.04) · Docker Engine ───────────┐   │
│   │  Caddy  — TLS termination, internal certificate            │   │
│   │  Open WebUI  :8080  (expose only, never published)         │   │
│   │  Persistent storage on a managed data disk                 │   │
│   └────────────────────────────────────────────────────────────┘   │
│                                                                    │
│   Azure OpenAI  — model deployment, completions over HTTPS         │
│   Log Analytics — VM metrics, alert rules, action group            │
└────────────────────────────────────────────────────────────────────┘
```

Single-node, internal-use deployment. Port 8080 is never published to the host, so Caddy is the only way in. See [docs/architecture.md](docs/architecture.md) for the full diagram and trust boundaries.

---

## Repository structure

```
.
├── terraform/   # Part 1 — resource group, VNet/subnet, NSG, static IP, VM, data disk
├── scripts/     # Part 2 — Bash automation, numbered 00 through 12
├── docker/      # Part 3 — docker-compose.yml, Caddyfile, env.example
└── docs/        # Part 4 — architecture, deployment, operations, security, troubleshooting, employee guide
```

### Scripts

| Script | Part | Purpose |
|---|---|---|
| `00-prepare.sh` | 2 | OS updates, firewall baseline, format and mount the data disk |
| `01-install-docker.sh` | 2 | Install Docker Engine and the Compose plugin |
| `02-deploy.sh` | 2 | Pull images and start the Compose stack |
| `03-validate.sh` | 2 | Container and HTTPS smoke test |
| `04-access-check.sh` | 4 | Access-control checks: TLS, port privacy, authentication |
| `backup.sh` | 2 | Back up and restore the Open WebUI data directory |
| `10-harden.sh` | 4 | SSH, host firewall, fail2ban, Docker log rotation |
| `11-validate.sh` | 4 | Full system health check |
| `11-restart.sh` | 2 | Ordered restart with verification |
| `12-cleanup.sh` | 2 | Application teardown; `--terraform` removes the Azure resources |

---

## Deployment flow

1. Set `terraform.tfvars` (subscription, allow-list, SSH public key) and run `terraform apply`
2. Copy `docker/` and `scripts/` to the VM, then run `00-prepare.sh` and `01-install-docker.sh`
3. Copy `docker/env.example` to `docker/.env`, fill in the Azure OpenAI key, and set `chmod 600`
4. Run `02-deploy.sh`, then create the Azure OpenAI account and model deployment
5. Run `10-harden.sh` with the allow-list, then `docker compose up -d --force-recreate` to apply log rotation
6. Run `11-validate.sh` and open the site from an allowed address

Full detail, including teardown and the reproducibility notes, is in [docs/deployment.md](docs/deployment.md).

> No real address is written down anywhere in this repository. The public IP is
> reallocated on every destroy and rebuild, and an administrator's own address
> may be dynamic — so read the current value with
> `terraform output -raw public_ip` rather than copying it from the docs.

---

## Security notes

- **Secrets are never committed.** Only `env.example` with placeholders is tracked; `.env` is git-ignored and set to mode `600` on the VM.
- **Access is allow-list only.** The NSG permits 22 and 443 from listed addresses and denies everything else. The host firewall mirrors it, including a `DOCKER-USER` chain because Docker's port publishing otherwise bypasses the firewall entirely.
- **Registration is open, access is not.** Anyone on an allow-listed address can request an account, but every new account lands as `pending` and can do nothing until an administrator approves it.
- **SSH is key-only.** Root login and password authentication are disabled; fail2ban bans repeat offenders, with the allow-list excluded so an administrator cannot lock themselves out.
- **Images are pinned by digest**, so `compose pull` cannot change the build under a live database.
- The certificate is issued by an internal CA, so browsers show a warning on first visit. Traffic is still encrypted.

Control-by-control detail, including how each was verified and the known gaps, is in [docs/security.md](docs/security.md).

---

## Deliverables

- [x] Terraform configuration for the Azure infrastructure
- [x] Bash automation for provisioning, validation, restart, backup, and teardown
- [x] Docker Compose deployment definition with a TLS-terminating reverse proxy
- [x] Environment variable template with no real values
- [x] Azure OpenAI account and model deployment
- [x] Host hardening, monitoring, and alert rules
- [x] Operations, security, troubleshooting, and user documentation

---

## Acceptance criteria

- [x] Azure resources are provisioned successfully through Terraform
- [x] Open WebUI is deployed through automation scripts
- [x] The application starts reliably with Docker Compose
- [x] Access is configured securely, and a non-allowed address is provably blocked
- [x] The platform supports a realistic AI assistance workflow, including document upload and retrieval
- [x] Chats, users, and settings survive restarts, reboots, and a full destroy/rebuild
- [x] Documentation supports operational deployment, day-two use, and troubleshooting

---

## What went wrong along the way

The most useful part of this project is not the architecture diagram — it is the failures. Each of these occurred for real, was diagnosed, and is documented with its cause in [docs/troubleshooting.md](docs/troubleshooting.md):

- `terraform destroy` stopped halfway and reported nothing useful, because the resource group is a Terraform resource but the Azure OpenAI and monitoring resources inside it are not.
- A firewall rule took the application offline: matching only on destination port also matched the containers' outbound traffic, cutting Open WebUI off from the model API.
- `iptables-restore` silently disabled the host firewall while `ufw status` still reported it active.
- fail2ban was configured correctly and banned nobody, because its journal matched a systemd unit that does not exist.
- Two alert rules used metric names that do not exist and silently evaluated nothing.

The recurring lesson is that most of these produced a system that *looked* healthy while doing nothing. Verification has to interrogate live state — the kernel's firewall policy, the alert status endpoint, an actual brute force — rather than trusting that a configuration file was accepted.

---

## Known limitations

Listed in full in [docs/security.md](docs/security.md). In short: container and syslog logs are not centralised to Azure (only metrics are), alert rules have never been deliberately fired end to end, the deployment is a single VM with no high availability, and sessions last up to four weeks with no server-side revocation.

---

## Timeline

| Week | Work |
|---|---|
| 3 | Proposal presentation and architecture design |
| 4 | Part 1 — Azure design and Terraform provisioning |
| 5 | Parts 2 and 3 — Bash automation, Open WebUI deployment, AI backend integration |
| 6 | Part 4 — Hardening, monitoring, testing, and documentation |
| 7 | Destroy/rebuild verification, final presentation, and handover |