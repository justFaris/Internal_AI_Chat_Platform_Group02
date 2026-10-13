# Security Documentation

## Overview

This document describes the security controls implemented for the Internal AI Chat Platform based on Open WebUI, deployed on Microsoft Azure.

## 1. Network Security

- Azure Network Security Groups (NSG) restrict inbound traffic to approved IP addresses.
- SSH access is restricted to authorized IP addresses.
- Web access is controlled through Azure NSG rules.
- SSH Tunnel provides encrypted access to Open WebUI for administration and testing.

## 2. SSH Security

- SSH public-key authentication is enabled.
- Password authentication is disabled.
- Keyboard-interactive authentication is disabled.
- SSH access is restricted through Azure NSG.

## 3. User Authentication and Access Control

- Open WebUI requires user authentication.
- New user self-registration is disabled.
- Admin and User roles have separate permissions.
- Administrators manage user accounts and AI model access.
- Users cannot access other users' private conversations.
- Unauthorized access to the Admin Panel is restricted.

## 4. Secret Management

- API keys and application secrets are stored in a local `.env` file.
- File permissions are restricted to `600`.
- Sensitive configuration files are excluded from Git.
- The `.env.example` file provides configuration templates without real credentials.

## 5. Container and OS Security

- Open WebUI runs inside a Docker container.
- Docker AppArmor protection is enabled.
- The container runs without privileged mode.
- Automatic security updates are configured on Ubuntu.
- Docker Compose manages application startup and restart.

## 6. Data Protection

- Open WebUI stores application data in a persistent Docker volume.
- User accounts, conversations, and uploaded documents remain available after restart and redeployment.
- Application data is preserved during default cleanup operations.
- AI requests are processed through the configured Gemini API backend.

## 7. Secure Access Considerations

- SSH Tunnel provides an encrypted connection between the client and Azure VM.
- The current application configuration uses HTTP on port 80.
- Direct HTTP traffic is not encrypted and is restricted through Azure NSG.
- Sensitive company documents should only be submitted to external AI services according to organizational data policies.

## 8. Security Validation

The following controls were successfully verified:

| Security Test | Result |
|---|---|
| NSG Access Restrictions | PASS |
| SSH Key Authentication | PASS |
| User Authentication | PASS |
| Role-Based Access Control | PASS |
| Model Access Permissions | PASS |
| Conversation Access Isolation | PASS |
| Secret File Permissions | PASS |
| Git Secret Protection | PASS |
| AppArmor Protection | PASS |
| Docker Privileged Mode Disabled | PASS |

## Conclusion

The implemented security controls provide restricted network access, user authentication, role-based permissions, secret protection, and container security for the Open WebUI platform.