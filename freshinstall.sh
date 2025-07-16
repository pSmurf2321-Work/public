#!/bin/bash
set -euo pipefail

echo ">>> Updating system..."
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

echo ">>> Installing hardware drivers (if available)..."
sudo ubuntu-drivers autoinstall || echo "No proprietary drivers found or required."

echo ">>> Installing common utilities..."
sudo apt install -y \
  curl wget git net-tools lsd mc micro rclone \
  btop tldr bash-completion resolvconf wireguard-tools openssh-server

echo ">>> Removing any old Docker packages..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  sudo apt-get remove -y $pkg || true
done

echo ">>> Installing Docker with official repo and GPG key..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo \"$UBUNTU_CODENAME\") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Enabling and starting SSH..."
sudo systemctl enable ssh
sudo systemctl start ssh

echo ">>> Installing micro editor from getmic.ro..."
cd /usr/local/bin && sudo curl -fsSL https://getmic.ro | sudo bash
sudo chmod +x /usr/local/bin/micro

echo ">>> Installing WireGuard kernel support..."
sudo apt install -y linux-headers-$(uname -r) dkms wireguard-dkms
sudo modprobe wireguard || echo "WireGuard module load failed"

echo ">>> Installing WireGuard Manager..."
sudo curl -fsSL https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh -o /usr/local/bin/wireguard-manager.sh
sudo chmod +x /usr/local/bin/wireguard-manager.sh

echo ">>> Launching WireGuard Manager (interactive)..."
sudo bash /usr/local/bin/wireguard-manager.sh
