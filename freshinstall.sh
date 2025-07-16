#!/bin/bash

# Exit on errors, unset vars, and pipe failures
set -euo pipefail

echo ">>> Updating system..."
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

echo ">>> Installing hardware drivers (if available)..."
sudo ubuntu-drivers autoinstall || echo "No proprietary drivers found or required."

echo ">>> Installing common utilities..."
sudo apt install -y \
  curl wget git net-tools lsd mc micro rclone \
  btop tldr bash-completion resolvconf wireguard-tools openssh-server

echo ">>> Removing old Docker packages if any..."
sudo apt-get purge -y docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc || true
sudo apt-get autoremove -y

echo ">>> Enabling and starting SSH..."
sudo systemctl enable ssh
sudo systemctl start ssh

echo ">>> Installing micro (latest from getmic.ro)..."
sudo bash -c "cd /usr/local/bin && curl -fsSL https://getmic.ro | bash"
sudo chmod +x /usr/local/bin/micro

echo ">>> Adding Docker's official GPG keyring..."
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker-archive-keyring.gpg
sudo chmod a+r /etc/apt/keyrings/docker-archive-keyring.gpg

echo ">>> Adding Docker repository..."
echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update

echo ">>> Installing Docker Engine and tools..."
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Adding current user to docker group (requires logout/login)..."
sudo usermod -aG docker "$USER" || echo "Failed to add user to docker group."

echo ">>> Installing WireGuard kernel support..."
sudo apt install -y linux-headers-$(uname -r) dkms wireguard-dkms
sudo modprobe wireguard || echo "WireGuard module load failed"
lsmod | grep wireguard || echo "WireGuard module not loaded"

echo ">>> Installing WireGuard Manager..."
sudo curl -fsSL \
  https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh \
  -o /usr/local/bin/wireguard-manager.sh
sudo chmod +x /usr/local/bin/wireguard-manager.sh

echo ">>> Launching WireGuard Manager (interactive)..."
sudo bash /usr/local/bin/wireguard-manager.sh
