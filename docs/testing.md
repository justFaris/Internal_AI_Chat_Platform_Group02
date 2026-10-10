# Testing and Validation

## Scope

This document records the acceptance and security tests performed by the Security, Testing, and Documentation role in the project test environment.

## Acceptance Test Results

| # | Criterion | Test / Action | Expected Result | Actual Result | Status |
|---|---|---|---|---|---|
| 1 | Terraform configuration valid | `terraform validate` | Configuration is valid | Validation successful | PASS |
| 2 | Monitoring resources plan | `terraform plan` | 3 resources to add, no changes or destruction | 3 to add, 0 to change, 0 to destroy | PASS |
| 3 | Azure Monitor resources deployment | `terraform apply` | Action Group + CPU Alert + Memory Alert created | 3 resources added | PASS |
| 4 | Alert notification | Test Azure Monitor Action Group | Test email received | Email received successfully | PASS |
| 5 | Open WebUI container | `docker compose ps` | Open WebUI running and healthy | Container healthy | PASS |
| 6 | Caddy reverse proxy | `docker compose ps` and logs | Caddy running normally | Caddy running | PASS |
| 7 | HTTPS access | Access application through port 443 | Application accessible using HTTPS | HTTPS working | PASS |
| 8 | HTTPS health endpoint | `validate.sh` health check | HTTP 200 | HTTP 200 returned | PASS |
| 9 | Port 8080 exposure | Network/listening-port validation | Port 8080 not publicly exposed | Port 8080 not exposed | PASS |
| 10 | NSG approved HTTPS source | Azure Network Watcher IP Flow Verify | Approved source allowed to port 443 | Access allowed | PASS |
| 11 | NSG unauthorized source | Azure Network Watcher IP Flow Verify | Unauthorized source denied | Denied by DenyAllInBound | PASS |
| 12 | Effective NSG rules | Network Watcher Effective Security Rules | SSH/HTTPS allow rules and deny rule visible | Rules verified | PASS |
| 13 | SSH hardening | `sshd -T` | Password/root login disabled; key auth enabled | Settings verified | PASS |
| 14 | Host firewall | `ufw status` | UFW active | UFW active | PASS |
| 15 | Brute-force protection | `fail2ban-client status sshd` | SSH jail active | Fail2ban active | PASS |
| 16 | Secret file permissions | Check `.env` permissions | Permission 600 | Permission 600 | PASS |
| 17 | Repository secret scan | Gitleaks scan | No secrets detected | No leaks found | PASS |
| 18 | Persistent storage | Restart/down-up/reboot tests | Open WebUI data remains available | Data persisted | PASS |
| 19 | Backup creation | `backup.sh` | Valid backup archive created | Backup created successfully | PASS |
| 20 | Restore test | Restore previous backup | Earlier data restored correctly | Restore successful | PASS |
| 21 | Automated validation | `validate.sh` | 0 failures and 0 warnings | 0 failed, 0 warnings | PASS |
| 22 | Failure detection — application | Stop Open WebUI and run `validate.sh` | Application and HTTPS checks fail | 2 failures detected, exit code 1 | PASS |
| 23 | Failure detection — secret permissions | Change `.env` to 644 | Validation detects incorrect permission | Failure detected | PASS |
| 24 | Controlled restart | `restart.sh` | Containers restart and validation succeeds | 0 failed, 0 warnings | PASS |
| 25 | CPU monitoring | Azure Monitor Metrics | CPU metric visible | Metric displayed successfully | PASS |
| 26 | Memory monitoring | Azure Monitor Metrics | Available memory metric visible | Metric displayed successfully | PASS |
| 27 | Network monitoring | Network In / Network Out metrics | Network metrics visible | Metrics displayed successfully | PASS |
## Result
All tested acceptance criteria passed in the security and testing environment.