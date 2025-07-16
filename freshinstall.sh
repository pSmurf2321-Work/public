#!/bin/bash

# Exit immediately if a command exits with a non-zero status,
# treat unset variables as an error, and fail on pipe errors.
set -euo pipefail

echo ">>> Updating system..."
# Update package lists, upgrade installed packages, and remove unnecessary packages
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

echo ">>> Installing hardware drivers (if available)..."
# Automatically install any available proprietary drivers (e.g., GPU drivers)
sudo ubuntu-drivers autoinstall || echo "No proprietary drivers found or required."

echo ">>> Installing common utilities..."
# Install frequently used utilities and tools
sudo apt install -y \
  curl wget git net-tools lsd mc micro rclone \
  btop tldr bash-completion resolvconf wireguard-tools openssh-server

echo ">>> Removing old Docker packages if any..."
# Purge any existing Docker, Docker Compose, Podman or containerd packages that might conflict
sudo apt-get purge -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
sudo apt-get autoremove -y

echo ">>> Enabling and starting SSH..."
# Enable SSH service to start on boot and start it immediately
sudo systemctl enable ssh
sudo systemctl start ssh

echo ">>> Installing micro (latest from getmic.ro)..."
# Download and install the latest 'micro' text editor binary to /usr/local/bin
cd /usr/local/bin && sudo curl -fsSL https://getmic.ro | sudo bash
sudo chmod +x /usr/local/bin/micro

echo ">>> Adding Docker's official GPG key..."
# Create directory for apt keyrings if it doesn't exist
sudo install -m 0755 -d /etc/apt/keyrings
# Download and save Docker's official GPG key
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.gpg
# Set permissions so apt can read the key
sudo chmod a+r /etc/apt/keyrings/docker.gpg

echo ">>> Adding Docker repository..."
# Add Docker's official stable repository for your Ubuntu version to apt sources list
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package lists after adding new repo
sudo apt-get update

echo ">>> Installing Docker Engine and tools..."
# Install Docker Engine, CLI, containerd runtime, Buildx and Compose plugins
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Installing WireGuard kernel support..."
# Install Linux headers, DKMS, and WireGuard kernel module package
sudo apt install -y linux-headers-$(uname -r) dkms wireguard-dkms
# Attempt to load WireGuard kernel module immediately
sudo modprobe wireguard || echo "WireGuard module load failed"
# Verify WireGuard kernel module is loaded; print message if not
lsmod | grep wireguard || echo "WireGuard module not loaded"

echo ">>> Installing WireGuard Manager..."
# Download WireGuard Manager script to /usr/local/bin
sudo curl -fsSL \
  https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh \
  -o /usr/local/bin/wireguard-manager.sh
# Make WireGuard Manager script executable
sudo chmod +x /usr/local/bin/wireguard-manager.sh

echo ">>> Launching WireGuard Manager (interactive)..."
# Run the WireGuard Manager script (interactive setup)
sudo bash /usr/local/bin/wireguard-manager.sh
