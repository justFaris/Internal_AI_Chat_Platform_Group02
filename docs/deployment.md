# Deployment Guide

## 1. Prerequisites
List the tools and access required before deployment, such as Azure CLI, Terraform, Git, SSH, and access to the Azure subscription. Sensitive information such as API keys, `.env` files, SSH private keys, and Terraform state must not be committed to GitHub.

## 2. Provision Azure Infrastructure
Explain that the Azure infrastructure is provisioned using Terraform.

Main commands:

`terraform init`  
`terraform validate`  
`terraform plan`  
`terraform apply`

The deployment should create the required networking, compute, storage, and security resources.

## 3. Connect to the Virtual Machine
Connect to the Azure VM using SSH key authentication.

Password-based SSH access should remain disabled.

## 4. Prepare the VM
Run the setup script to prepare the Linux host.

The setup process should:

- install Docker
- install Docker Compose
- prepare persistent storage
- create application directories
- apply operating system security settings

## 5. Configure Environment Variables
Create the `.env` file and add the required application configuration.

The file should contain environment-specific values such as application secrets, AI API credentials, model endpoints, and image versions.

Set secure permissions:

`chmod 600 .env`

The `.env` file must not be committed to GitHub.

## 6. Deploy Open WebUI
Start the application using Docker Compose.

`docker compose up -d`

Verify the containers:

`docker compose ps`

Open WebUI should be running successfully before continuing.

## 7. Configure Open WebUI
After the application starts:

- create the administrator account
- configure the AI backend
- disable unnecessary public registration
- verify user access controls
- test a new AI chat

## 8. Security Verification
Verify the main security controls, including:

- Azure NSG restrictions
- limited public port exposure
- SSH key authentication
- secure `.env` permissions
- disabled public registration
- allowed and denied traffic using Azure Network Watcher

## 9. Deployment Validation
Run the validation script after deployment.

The validation should verify:

- Docker service status
- persistent storage
- Open WebUI health
- Caddy status
- required ports
- restricted port exposure
- security services
- application health endpoint

Expected result:

`0 failed, 0 warnings`

## 10. Monitoring
Use Azure Monitor to review:

- CPU usage
- available memory
- network traffic

Configure alerts for conditions such as:

- high CPU usage
- low available memory

## 11. Backup and Recovery
Create regular backups of Open WebUI persistent data.

Backups should be stored securely because they may contain application and user data.

A restore test should be performed to confirm that application data can be recovered successfully.

## 12. Troubleshooting
Common troubleshooting areas include:

- SSH connectivity
- Azure NSG rules
- Docker container health
- application ports
- AI backend connectivity
- environment configuration

