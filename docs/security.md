# Security Documentation

## Security and Operational Considerations

Security is a major requirement for this platform.

The project implements the following security controls:

- Restricted access controls
- Secure secret management
- Limited exposure to public networking
- Operating system hardening
- Deployment and troubleshooting documentation

## Implemented Security Controls

| Control | Implementation | Verification | Status |
|---|---|---|---|
| Network access control | Azure VNet, Subnet and NSG | Unauthorized mobile network was blocked | PASS |
| HTTPS access | Caddy reverse proxy on port 443 | HTTPS connection tested successfully | PASS |
| Private application port | Open WebUI port 8080 is internal only | External connection timed out | PASS |
| Public registration | New Sign Ups disabled | Sign-up option not available | PASS |
| User permissions | Default role pending and user/admin separation | Test user had no Admin Panel | PASS |
| SSH hardening | Root/password login disabled, key authentication enabled | Verified using `sshd -T` | PASS |
| Host firewall | UFW enabled for SSH and HTTPS | `ufw status verbose` | PASS |
| Brute-force protection | Fail2ban SSH jail enabled | `fail2ban-client status sshd` | PASS |
| Automatic updates | unattended-upgrades enabled | Dry-run completed successfully | PASS |
| Docker log rotation | 10 MB x 3 files | Docker LogConfig verified | PASS |
| Image pinning | Open WebUI and Caddy use fixed versions | Docker images verified | PASS |
| Secret protection | `.env` permission 600 and excluded from Git | Gitleaks: no leaks found | PASS |
| Reproducible hardening | Hardening included in `setup.sh` | Script successfully executed twice | PASS |
## Network Security Design

The platform uses Azure networking controls to reduce public exposure.

Traffic flow:

Client ==> NSG ==> HTTPS 443 ==> Caddy ==> Open WebUI 8080

The NSG restricts inbound traffic based on approved source IP addresses and allowed ports. Open WebUI port 8080 is not exposed directly to the Internet.

## Monitoring and Troubleshooting

Azure Network Watcher will be used in the monitoring phase to validate network connectivity, inspect effective security rules, and troubleshoot NSG-related connectivity issues.
