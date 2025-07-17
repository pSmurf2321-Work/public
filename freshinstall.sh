#!/bin/bash
# Run this script with sudo: sudo ./setup.sh
set -euo pipefail

# Determine real user invoking sudo (or fallback to root)
USER_NAME="${SUDO_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$USER_NAME")

echo ">>> Running as user: $USER_NAME"
echo ">>> User home directory: $USER_HOME"

echo ">>> Updating package lists and installing base tools..."
apt update
apt install -y curl ca-certificates gnupg lsb-release

echo ">>> Upgrading system packages..."
apt upgrade -y
apt autoremove -y

echo ">>> Installing hardware drivers (if available)..."
if ! ubuntu-drivers autoinstall; then
  echo "No proprietary drivers found or required."
fi

echo ">>> Installing common utilities..."
apt install -y \
  curl wget git net-tools lsd mc micro rclone \
  btop tldr bash-completion resolvconf wireguard-tools openssh-server

echo ">>> Removing old Docker packages if any..."
apt-get purge -y docker.io docker-doc docker-compose docker-compose-plugin podman-docker containerd runc || true
apt-get autoremove -y

echo ">>> Enabling and starting SSH service..."
systemctl enable ssh
systemctl start ssh

echo ">>> Installing latest micro editor from GitHub releases..."
MICRO_BIN="/usr/local/bin/micro"
if ! command -v micro &> /dev/null; then
  MICRO_LATEST_URL=$(curl -s https://api.github.com/repos/zyedidia/micro/releases/latest | grep browser_download_url | grep linux64.tar.gz | cut -d '"' -f 4)
  TMPDIR=$(mktemp -d)
  curl -L "$MICRO_LATEST_URL" -o "$TMPDIR/micro.tar.gz"
  tar -xzf "$TMPDIR/micro.tar.gz" -C "$TMPDIR"
  install "$TMPDIR/micro" "$MICRO_BIN"
  chmod +x "$MICRO_BIN"
  rm -rf "$TMPDIR"
else
  echo "micro already installed, skipping."
fi

echo ">>> Setting up Docker repository and installing Docker..."
if [ ! -f /etc/apt/keyrings/docker-archive-keyring.gpg ]; then
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | tee /etc/apt/keyrings/docker-archive-keyring.gpg > /dev/null
  chmod a+r /etc/apt/keyrings/docker-archive-keyring.gpg
fi

ARCH=$(dpkg --print-architecture)
UBUNTU_CODENAME=$(lsb_release -cs)

DOCKER_LIST_FILE="/etc/apt/sources.list.d/docker.list"
if ! grep -q "download.docker.com" "$DOCKER_LIST_FILE" 2>/dev/null; then
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" > "$DOCKER_LIST_FILE"
fi

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Adding user '$USER_NAME' to docker group (logout/login required)..."
if groups "$USER_NAME" | grep -q '\bdocker\b'; then
  echo "User '$USER_NAME' is already in docker group."
else
  usermod -aG docker "$USER_NAME"
  echo "User '$USER_NAME' added to docker group."
fi

echo ">>> Installing WireGuard kernel support..."
apt install -y linux-headers-$(uname -r) dkms wireguard-dkms

if ! lsmod | grep -q wireguard; then
  if ! modprobe wireguard; then
    echo "Warning: WireGuard kernel module failed to load."
  else
    echo "WireGuard module loaded."
  fi
else
  echo "WireGuard module already loaded."
fi

echo ">>> Installing WireGuard Manager script..."
WIREGUARD_MANAGER_PATH="/usr/local/bin/wireguard-manager.sh"
curl -fsSL https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh -o "$WIREGUARD_MANAGER_PATH"
chmod +x "$WIREGUARD_MANAGER_PATH"

if [[ "${1:-}" == "--wg-manager" ]]; then
  echo ">>> Launching WireGuard Manager (interactive)..."
  bash "$WIREGUARD_MANAGER_PATH"
else
  echo "WireGuard Manager install complete. To launch it interactively, run:"
  echo "  sudo bash $WIREGUARD_MANAGER_PATH"
  echo "Or rerun this script with --wg-manager argument."
fi

echo ">>> Cloning HomeServer config repo to $USER_HOME/HomeServer..."
HOMESERVER_DIR="$USER_HOME/HomeServer"

if [ -d "$HOMESERVER_DIR" ]; then
  echo "HomeServer directory already exists. Attempting to update..."
  git -C "$HOMESERVER_DIR" pull --rebase || echo "Git pull failed. You may want to check repository manually."
else
  sudo -u "$USER_NAME" git clone https://github.com/pSmurf2321-Work/HomeServer.git "$HOMESERVER_DIR"
fi

echo ">>> Setup complete. Remember to logout and login again for docker group changes to apply."
