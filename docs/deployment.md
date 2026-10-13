# Deployment Guide

## Overview

This guide explains how to deploy, configure, and operate the Internal AI Chat Platform using Microsoft Azure, Terraform, Docker Compose, Bash scripts, and Open WebUI.

## 1. Prerequisites

Required tools:

- Azure CLI
- Terraform
- Git
- SSH Client
- Docker Engine
- Docker Compose v2

Windows 11 is used for Azure and Terraform administration, while Ubuntu 24.04 LTS hosts Open WebUI.

## 2. Azure Login

Sign in to Azure using Windows PowerShell:

```powershell
az login
az account show -o table
```

## 3. Terraform Configuration

**Environment: Windows PowerShell**

Navigate to the Terraform directory from the project root:

```powershell
cd terraform
```

Configure the required variables locally in `terraform.tfvars`:

```hcl
subscription_id = "<your-subscription-id>"
allowed_cidrs   = ["<approved-public-ip>/32"]
```

Do not commit sensitive configuration values to Git.

## 4. Terraform Deployment

**Environment: Windows PowerShell**

From the Terraform directory, run:

```powershell
terraform init
terraform validate
terraform plan
terraform apply
```

Terraform provisions the Azure infrastructure, including the Resource Group, networking resources, NSG, Public IP, Ubuntu VM, and managed data disk.

## 5. Connect to the Azure VM

**Environment: Windows PowerShell**

Use SSH Key Authentication:

```powershell
ssh -i "$HOME\.ssh\openwebui" "azureuser@$(terraform output -raw public_ip)"
```

Run this command from the Terraform directory.

## 6. Prepare the Project

**Environment: Azure Ubuntu VM**

Transfer or clone the project repository to the Azure VM.

The project directory is:

```text
~/Internal_AI_Chat_Platform_Group02
```

Navigate to the project root:

```bash
cd ~/Internal_AI_Chat_Platform_Group02
```

## 7. VM Setup

**Environment: Azure Ubuntu VM**

From the project root, run:

```bash
bash scripts/vm_setup.sh
```

The current setup script installs Docker, Docker Compose v1, and Git, and enables the Docker service.

Install Docker Compose v2 separately:

```bash
sudo apt-get install -y docker-compose-v2
```

Verify the installation:

```bash
docker compose version
```

A new SSH session may be required after adding the user to the Docker group.

The setup script currently requires a separate Docker Compose v2 installation. Updating this dependency is part of the Bash automation improvements.

## 8. Environment Configuration

**Environment: Azure Ubuntu VM**

Navigate to the Docker directory:

```bash
cd ~/Internal_AI_Chat_Platform_Group02/docker
```

Create a local `.env` file using the required variables:

```env
WEBUI_SECRET_KEY=<your-secret-key>
OPENAI_API_KEY=<your-gemini-api-key>
```

Generate a secret key using:

```bash
openssl rand -hex 32
```

Protect the environment file:

```bash
chmod 600 .env
```

Never commit `.env` or actual API keys to Git.

## 9. Validate Docker Compose

**Environment: Azure Ubuntu VM**

From the Docker directory, verify the configuration:

```bash
docker compose config --quiet
```

The command should complete without errors.

## 10. Deploy Open WebUI

**Environment: Azure Ubuntu VM**

From the Docker directory, run:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

The application uses host port `80` and container port `8080`.

Verify that the container reaches the `healthy` state.

## 11. Access Open WebUI

**Environment: Windows PowerShell**

For encrypted administrative and demonstration access, use an SSH Tunnel.

Navigate to the Terraform directory:

```powershell
cd C:\team-project\Internal_AI_Chat_Platform_Group02\terraform
```

Start the SSH Tunnel:

```powershell
ssh -i "$HOME\.ssh\openwebui" -o ExitOnForwardFailure=yes -L 8080:localhost:80 "azureuser@$(terraform output -raw public_ip)"
```

Keep the SSH session open.

Access Open WebUI through the browser:

```text
http://localhost:8080
```

The SSH Tunnel encrypts traffic between Windows and the Azure VM.

The current deployment also binds HTTP port 80 to the VM network interfaces. Azure NSG restricts inbound access to approved IP addresses. Direct HTTP connections are not encrypted.

## 12. Deployment Validation

**Environment: Azure Ubuntu VM**

Navigate to the project root:

```bash
cd ~/Internal_AI_Chat_Platform_Group02
```

Run the validation script:

```bash
bash scripts/validate.sh
```

The successfully tested deployment returned:

```text
Result: 0 failed, 0 warnings
```

The validation result applies to the checks implemented in `validate.sh`.

## 13. Restart Open WebUI

**Environment: Azure Ubuntu VM**

Navigate to the project root:

```bash
cd ~/Internal_AI_Chat_Platform_Group02
```

Restart the existing application:

```bash
bash scripts/restart.sh
```

Recreate the container using Docker Compose v2:

```bash
bash scripts/restart.sh --recreate
```

The `--recreate` option uses Docker Compose to create or recreate the application container.

The script performs application validation after restarting.

## 14. Cleanup

**Environment: Azure Ubuntu VM**

Navigate to the project root:

```bash
cd ~/Internal_AI_Chat_Platform_Group02
```

Stop and remove the application container and Compose network:

```bash
bash scripts/cleanup.sh
```

The default cleanup preserves persistent application data.

Do not use `--delete-volume` unless permanent data deletion is intended.

## 15. Persistent Data

Open WebUI stores its application data in the Docker volume:

```text
docker_open-webui-data
```

Testing confirmed that user accounts, conversation history, and uploaded documents remained available after application restart, container recreation, cleanup and redeployment, and Azure VM restart.

The Docker named volume is separate from the attached Azure managed data disk.

## 16. Troubleshooting

**Environment: Azure Ubuntu VM**

Navigate to the Docker directory:

```bash
cd ~/Internal_AI_Chat_Platform_Group02/docker
```

Check the container status:

```bash
docker compose ps
```

View application logs:

```bash
docker compose logs --tail=100 open-webui
```

Check the application health endpoint using an HTTP GET request:

```bash
curl -fsS http://localhost/health
```

To run the full deployment validation, navigate to the project root:

```bash
cd ~/Internal_AI_Chat_Platform_Group02
```

Then run:

```bash
bash scripts/validate.sh
```

## 17. Stop the Application

**Environment: Azure Ubuntu VM**

Navigate to the Docker directory:

```bash
cd ~/Internal_AI_Chat_Platform_Group02/docker
```

To stop the application while preserving persistent storage:

```bash
docker compose down
```

The Docker volume remains available for subsequent deployments.

## 18. Deployment Notes

- Azure infrastructure is managed using Terraform.
- The VM environment is prepared using Bash automation.
- Docker Compose v2 is used for application deployment and lifecycle management.
- Open WebUI is accessed through an SSH Tunnel for administrative testing.
- Application data is preserved using a persistent Docker volume.
- Deployment validation is performed using `validate.sh`.
- The first-time deployment workflow has been documented, but complete end-to-end automation from a fresh VM has not yet been verified.
- HTTPS/TLS is not currently configured for direct web access.
- The Gemini API is an external AI service, so data sent to the model is processed outside the Azure VM.