# Deployment Guide

## Overview

This guide explains how to deploy and run the Internal AI Chat Platform using Azure, Terraform, Docker Compose, and Open WebUI.

## 1. Prerequisites

Install the following tools:

- Azure CLI
- Terraform
- Git
- Docker
- Docker Compose
- SSH client
- WSL when working from Windows

Verify the tools:

```bash
az --version
terraform -version
git --version
docker --version
docker compose version
```

If the environment uses the legacy Docker Compose command, verify it using:

```bash
docker-compose --version
```

## 2. Azure Login

Sign in to Azure:

```bash
az login
```

Verify the active subscription:

```bash
az account show -o table
```

## 3. Terraform Configuration

Go to the Terraform directory:

```bash
cd terraform
```

The Terraform configuration requires values for:

- `subscription_id`
- `allowed_cidrs`

These values can be provided through a local `terraform.tfvars` file.

Example:

```hcl
subscription_id = "<your-subscription-id>"
allowed_cidrs   = ["<approved-public-ip>/32"]
```

Do not commit environment-specific or sensitive configuration values to the repository.

## 4. Terraform Deployment

Initialize Terraform:

```bash
terraform init
```

Validate the configuration:

```bash
terraform validate
```

Review the deployment plan:

```bash
terraform plan
```

Deploy the infrastructure:

```bash
terraform apply
```

Terraform provisions the main Azure resources, including:

- Resource Group
- Virtual Network
- Subnet
- Network Security Group
- Public IP
- Network Interface
- Ubuntu Linux Virtual Machine
- Managed Data Disk

## 5. Connect to the VM

Connect using SSH:

```bash
ssh <username>@<public-ip>
```

SSH password authentication is disabled and access uses an SSH public key.

## 6. Clone the Project

After connecting to the VM, clone the project repository:

```bash
git clone <repository-url>
```

Move into the project directory:

```bash
cd Internal_AI_Chat_Platform_Group02
```

## 7. VM Setup

Run the VM setup script:

```bash
bash scripts/vm_setup.sh
```

The script:

- Updates Ubuntu packages
- Installs Docker
- Installs Docker Compose
- Installs Git
- Enables and starts Docker
- Adds the current user to the Docker group

After the Docker group change, a new login session may be required before Docker can be used without `sudo`.

## 8. Environment Configuration

Go to the Docker directory:

```bash
cd docker
```

Create a local `.env` file:

```env
WEBUI_SECRET_KEY=<your-secret-key>
OPENAI_API_KEY=<your-api-key>
```

The `.env` file is excluded from Git and must not be committed to the repository.

A secret key can be generated using:

```bash
openssl rand -hex 32
```

## 9. Validate Docker Compose

For Docker Compose v2:

```bash
docker compose config
```

If the environment provides the legacy Docker Compose command instead:

```bash
docker-compose config
```

The configuration should complete without errors.

## 10. Deploy Open WebUI

Using Docker Compose v2:

```bash
docker compose pull
docker compose up -d
docker compose ps
```

If the environment uses the legacy command:

```bash
docker-compose pull
docker-compose up -d
docker-compose ps
```

The current Docker configuration maps:

```text
Host port 80 → Open WebUI container port 8080
```

## 11. Access Open WebUI

For local testing:

```text
http://localhost
```

For an Azure deployment, access the application using the VM public IP from an approved network:

```text
http://<public-ip>
```

The Azure NSG restricts web and SSH access to approved CIDR ranges.

## 12. Deployment Validation

Return to the project root and run:

```bash
cd ..
./scripts/validate.sh
```

The validation script checks:

- Docker availability
- Docker Compose availability
- Docker Compose configuration
- Open WebUI container status
- Persistent storage
- Port 80 availability
- Open WebUI health endpoint
- `.env` availability

A successful local validation returns:

```text
Result: 0 failed, 0 warnings
```

## 13. Restart Open WebUI

From the project root:

```bash
./scripts/restart.sh
```

The script restarts Open WebUI, waits for the application to become available, and automatically runs `validate.sh`.

## 14. Cleanup

To stop the Docker stack safely:

```bash
./scripts/cleanup.sh
```

The default cleanup removes the running container and Docker network but keeps the persistent application data.

To remove Docker images:

```bash
./scripts/cleanup.sh --images
```

The persistent volume should only be deleted intentionally using:

```bash
./scripts/cleanup.sh --delete-volume
```

## 15. Persistent Data

Open WebUI stores application data in the Docker volume:

```text
open-webui-data
```

Local testing confirmed that the administrator account remained available after cleanup and redeployment.

## 16. Troubleshooting

Go to the Docker directory:

```bash
cd docker
```

Check the container status:

```bash
docker compose ps
```

View Open WebUI logs:

```bash
docker compose logs --tail=100 open-webui
```

Check the health endpoint:

```bash
curl http://localhost/health
```

To run the complete deployment validation from the project root:

```bash
cd ..
./scripts/validate.sh
```

If the container is still starting, wait for initialization to complete and check the logs again.

## 17. Stop the Application

From the Docker directory, stop the application while keeping its persistent data:

```bash
docker compose down
```

If the environment uses the legacy Docker Compose command:

```bash
docker-compose down
```

The `open-webui-data` volume remains available for the next deployment.