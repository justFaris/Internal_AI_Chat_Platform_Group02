#!/bin/bash

echo "Starting VM setup..."

# Update system packages
sudo apt update -y
sudo apt upgrade -y

# Install required tools
sudo apt install -y docker.io docker-compose git

# Enable Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add current user to Docker group
sudo usermod -aG docker $USER

echo "VM setup completed successfully!"