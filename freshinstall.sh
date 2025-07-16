#!/bin/bash

set -e

echo ">>> Updating system..."
sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y

echo ">>> Installing hardware drivers..."
sudo ubuntu-drivers autoinstall || echo "No proprietary drivers found or required."

echo ">>> Installing common utilities..."
sudo apt install -y \
  curl wget git net-tools fastfetch lsd mc micro rclone \
  btop tldr bash-completion resolvconf wireguard-tools openssh-server

echo ">>> Enabling and starting SSH..."
sudo systemctl enable ssh
sudo systemctl start ssh

echo ">>> Installing WireGuard Manager..."
sudo curl -fsSL \
  https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh \
  -o /usr/local/bin/wireguard-manager.sh
sudo chmod +x /usr/local/bin/wireguard-manager.sh

echo ">>> Launching WireGuard Manager (interactive)..."
sudo bash /usr/local/bin/wireguard-manager.sh
