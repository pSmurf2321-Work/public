#!/bin/bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$USER_NAME")

echo "Running as user: $USER_NAME"
echo "User home directory: $USER_HOME"

# --- 1. Check or create SSH key for GitHub access ---

SSH_KEY="$USER_HOME/.ssh/id_ed25519"
PUB_KEY="$SSH_KEY.pub"

if [ ! -f "$SSH_KEY" ]; then
  echo "No SSH key found. Generating new SSH key..."
  sudo -u "$USER_NAME" ssh-keygen -t ed25519 -C "setup@freshinstall" -f "$SSH_KEY" -N ""
  echo
  echo ">>> SSH public key (add this to your GitHub Deploy Keys or SSH keys):"
  cat "$PUB_KEY"
  echo
  echo "Add this SSH key to GitHub, then re-run this script."
  exit 1
fi

# Start ssh-agent and add key if not already added
eval "$(ssh-agent -s)" > /dev/null
ssh-add -l | grep -q "$SSH_KEY" || ssh-add "$SSH_KEY"

# --- 2. Clone or update private repo via SSH ---

HOMESERVER_DIR="$USER_HOME/HomeServer"

if [ ! -d "$HOMESERVER_DIR" ]; then
  echo "Cloning private repo via SSH..."
  sudo -u "$USER_NAME" git clone git@github.com:pSmurf2321-Work/HomeServer.git "$HOMESERVER_DIR"
else
  echo "Repo already cloned, pulling latest changes..."
  sudo -u "$USER_NAME" git -C "$HOMESERVER_DIR" pull --rebase
fi

# --- 3. Update & install base packages ---

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

# --- 4. Install latest micro editor from GitHub releases ---

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

# --- 5. Install Docker and set up repo ---

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

# --- 6. Install WireGuard kernel support ---

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

# --- 7. Install WireGuard Manager script ---

WIREGUARD_MANAGER_PATH="/usr/local/bin/wireguard-manager.sh"
curl -fsSL https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh -o "$WIREGUARD_MANAGER_PATH"
chmod +x "$WIREGUARD_MANAGER_PATH"

if [[ "${1:-}" == "--wg-manager" ]]; then
  echo ">>> Launching WireGuard Manager (interactive)..."
  bash "$WIREGUARD_MANAGER_PATH"
else
  echo "WireGuard Manager install complete."
  echo "To launch it interactively, run:"
  echo "  sudo bash $WIREGUARD_MANAGER_PATH"
fi

# --- 8. Final notes ---

echo
echo ">>> Setup complete!"
echo "Remember to log out and back in or reboot to apply docker group permissions."
echo "After that, place your .env file into $HOMESERVER_DIR if needed."
echo "Then run your start-services.sh script from $HOMESERVER_DIR to start your Docker services."

exit 0
