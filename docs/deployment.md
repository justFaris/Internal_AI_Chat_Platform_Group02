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

Navigate to the Terraform directory:

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

Run the following commands in Windows PowerShell:

```powershell
terraform init
terraform validate
terraform plan
terraform apply
```

Terraform provisions the Azure infrastructure, including the Resource Group, networking resources, NSG, Public IP, Ubuntu VM, and managed data disk.

## 5. Connect to the Azure VM

Use SSH Key Authentication from Windows PowerShell:

```powershell
ssh -i "$HOME\.ssh\openwebui" "azureuser@$(terraform output -raw public_ip)"
```

Run this command from the Terraform directory.

## 6. Prepare the Project

Transfer or clone the project repository to the Azure VM.

The project directory is:

```text
~/Internal_AI_Chat_Platform_Group02
```

## 7. VM Setup

Run the setup script on the Azure VM:

```bash
bash scripts/vm_setup.sh
```

The script installs Docker, Docker Compose v1, and Git, and enables the Docker service.

Install Docker Compose v2 separately:

```bash
sudo apt-get install -y docker-compose-v2
```

Verify the installation:

```bash
docker compose version
```

A new SSH session may be required after adding the user to the Docker group.

## 8. Environment Configuration

Navigate to the Docker directory:

```bash
cd docker
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

Verify the configuration:

```bash
docker compose config --quiet
```

The command should complete without errors.

## 10. Deploy Open WebUI

Run:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

The application uses host port `80` and container port `8080`.

Verify the container reaches the `healthy` state.

## 11. Access Open WebUI

For secure administrative and demonstration access, use an SSH Tunnel from Windows PowerShell.

Navigate to the Terraform directory and run:

```powershell
ssh -i "$HOME\.ssh\openwebui" -L 8080:localhost:80 "azureuser@$(terraform output -raw public_ip)"
```

Keep the SSH session open.

Access Open WebUI through the browser:

```text
http://localhost:8080
```

The SSH Tunnel encrypts traffic between Windows and the Azure VM.

The current deployment also binds HTTP port 80 to the VM network interfaces. Azure NSG restricts inbound access to approved IP addresses. Direct HTTP connections are not encrypted.

## 12. Deployment Validation

From the project root on the Azure VM:

```bash
bash scripts/validate.sh
```

Successful validation returns:

```text
Result: 0 failed, 0 warnings
```

## 13. Restart Open WebUI

Restart the application:

```bash
bash scripts/restart.sh
```

Recreate the container using Docker Compose v2:

```bash
bash scripts/restart.sh --recreate
```

The script performs application validation after restarting.

## 14. Cleanup

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

## 16. Troubleshooting

Check the container status:

```bash
docker compose ps
```

View application logs:

```bash
docker compose logs --tail=100 open-webui
```

Check the health endpoint:

```bash
curl -I http://localhost/health
```

Run the validation script from the project root to verify the deployment.

## 17. Stop the Application

To stop the application while preserving persistent storage:

```bash
docker compose down
```

The Docker volume remains available for subsequent deployments.