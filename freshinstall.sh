#!/bin/bash
set -euo pipefail

USER_NAME="${SUDO_USER:-$(whoami)}"
USER_HOME=$(eval echo "~$USER_NAME")

# --- Make sure $USER_HOME/bin exists
mkdir -p "$USER_HOME/bin"

# --- Add $USER_HOME/bin to PATH in ~/.bashrc if not already there
if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$USER_HOME/.bashrc"; then
  echo 'export PATH="$HOME/bin:$PATH"' >> "$USER_HOME/.bashrc"
  echo "Added \$HOME/bin to PATH in ~/.bashrc"
fi

# --- Source ~/.bashrc to update current session PATH (only if not already in PATH)
case ":$PATH:" in
  *":$USER_HOME/bin:"*) ;;
  *)
    echo "Sourcing ~/.bashrc to update PATH for this session"
    # shellcheck disable=SC1090
    source "$USER_HOME/.bashrc"
    ;;
esac

add_cronjob() {
  local label="$1"
  local job="$2"
  echo "[CRON] Installing: $label"
  ( crontab -l 2>/dev/null | grep -v "$label" ; echo "$job" ) | crontab -
}

echo "Setup done. You can now run generate-service-scripts.sh separately to generate scripts."

ENCRYPTED_KEY_URL="https://raw.githubusercontent.com/pSmurf2321-Work/HomeServer/main/keys/id_ed25519.enc"

SSH_KEY="$USER_HOME/.ssh/id_ed25519"
mkdir -p "$(dirname "$SSH_KEY")"

if [ ! -f "$SSH_KEY" ]; then
  echo "Downloading and decrypting SSH private key..."

  if [ -z "${DECRYPT_PASS:-}" ]; then
    read -rsp "Enter decryption password: " DECRYPT_PASS
    echo
  fi

  curl -fsSL "$ENCRYPTED_KEY_URL" -o "$USER_HOME/id_ed25519.enc"
  openssl aes-256-cbc -d -pbkdf2 -in "$USER_HOME/id_ed25519.enc" -out "$SSH_KEY" -pass pass:"$DECRYPT_PASS"
  
  chmod 600 "$SSH_KEY"
  rm "$USER_HOME/id_ed25519.enc"

  echo "SSH key restored and permissions set."
fi

# --- Start ssh-agent and add key if not already added
eval "$(ssh-agent -s)" > /dev/null
ssh-add -l | grep -q "$SSH_KEY" || ssh-add "$SSH_KEY"

echo "Running as user: $USER_NAME"
echo "User home directory: $USER_HOME"


# --- RCLONE CONFIG BACKUP & RESTORE ---
RCLONE_CONFIG_SRC="$USER_HOME/.config/rclone/rclone.conf"
BACKUP_DIR="$USER_HOME/backups/rclone"
RCLONE_CONFIG_BACKUP="$BACKUP_DIR/rclone.conf"

mkdir -p "$BACKUP_DIR"

if [[ -f "$RCLONE_CONFIG_SRC" ]]; then
  echo "[BACKUP] Saving rclone config to $RCLONE_CONFIG_BACKUP"
  cp "$RCLONE_CONFIG_SRC" "$RCLONE_CONFIG_BACKUP"
else
  echo "[BACKUP] No rclone config found at $RCLONE_CONFIG_SRC to backup."
fi

if [[ ! -f "$RCLONE_CONFIG_SRC" && -f "$RCLONE_CONFIG_BACKUP" ]]; then
  echo "[RESTORE] Restoring rclone config from backup."
  mkdir -p "$(dirname "$RCLONE_CONFIG_SRC")"
  cp "$RCLONE_CONFIG_BACKUP" "$RCLONE_CONFIG_SRC"
else
  echo "[RESTORE] No rclone config restore needed."
fi

# --- Check or create SSH key for GitHub access ---
SSH_KEY="$USER_HOME/.ssh/id_ed25519"
PUB_KEY="$SSH_KEY.pub"

# --- Docker GPG key and repository setup ---
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor | sudo tee /etc/apt/keyrings/docker-archive-keyring.gpg > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker-archive-keyring.gpg

ARCH=$(dpkg --print-architecture)
UBUNTU_CODENAME=$(lsb_release -cs)

echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list

sudo apt-get clean
sudo apt-get update

# --- Create required folders ---
export HOMESERVER_ROOT="$USER_HOME"

mkdir -p "$HOMESERVER_ROOT"/{backups/minecraft/server-{1,2},docker}
mkdir -p "$HOMESERVER_ROOT"/docker/{homepage/configs,minecraft/server-{1,2}/data,notifiarr/configs,nzbget/configs,portainer/data,prowlarr/configs,qbittorrent/configs,radarr/configs,sonarr/configs,wireguard/configs,watchtower,bazarr/configs,vpnclient/configs}
mkdir -p "$HOMESERVER_ROOT"/downloaded-media/{completed/{tv,movies},intermediate,incomplete,tmp}
mkdir -p "$HOMESERVER_ROOT/scripts"
mkdir -p "$HOMESERVER_ROOT/yaml"
mkdir -p "$HOMESERVER_ROOT/backups/logs/cron"
mkdir -p "$HOMESERVER_ROOT/duckdns"
sudo mkdir -p "/etc/wireguard"
sudo mkdir -p /media/HomeServer/PlexServer
sudo mkdir -p /media/HomeServer/PlexServerTV
sudo mkdir -p /data
sudo ln -s /media/HomeServer/PlexServerTV /data/PlexServerTV
sudo ln -s /media/HomeServer/PlexServer   /data/PlexServer

chown -R "$USER_NAME":"$USER_NAME" "$HOMESERVER_ROOT"

# --- Clone or update private repo via SSH ---
HOMESERVER_DIR="$USER_HOME/HomeServer"

if [ -d "$HOMESERVER_DIR" ]; then
  if [ ! -d "$HOMESERVER_DIR/.git" ]; then
    echo "Folder $HOMESERVER_DIR exists but is not a git repo. Removing it for fresh clone..."
    sudo rm -rf "$HOMESERVER_DIR"
  fi
fi

if [ ! -d "$HOMESERVER_DIR" ]; then
  echo "Cloning private repo via SSH..."
  sudo -u "$USER_NAME" git clone git@github.com:pSmurf2321-Work/HomeServer.git "$HOMESERVER_DIR"
else
  echo "Repo already cloned, pulling latest changes..."
  sudo -u "$USER_NAME" git -C "$HOMESERVER_DIR" pull --rebase
fi

# --- System update and base packages install ---
echo ">>> Updating package lists and installing base tools..."
sudo apt update
sudo apt install -y curl ca-certificates gnupg lsb-release

echo ">>> Upgrading system packages..."
sudo apt upgrade -y
sudo apt autoremove -y

echo ">>> Installing hardware drivers (if available)..."
if ! ubuntu-drivers autoinstall; then
  echo "No proprietary drivers found or required."
fi

# --- Utilities --- 
echo ">>> Installing common utilities..."
sudo apt install -y curl wget git xrdp python3 python3-pip net-tools lsd mc micro rclone btop tldr bash-completion resolvconf wireguard-tools openssh-server


echo ">>> Removing old Docker packages if any..."
sudo apt-get purge -y docker.io docker-doc docker-compose docker-compose-plugin podman-docker containerd runc || true
sudo apt-get autoremove -y

# --- SSH --- 
echo ">>> Enabling and starting SSH service..."
sudo systemctl enable ssh
sudo systemctl start ssh

# --- RDP --- 
echo ">>> Enabling and starting RDP service..."
sudo systemctl enable xrdp
sudo systemctl start xrdp


# --- Install latest micro editor from GitHub releases ---
MICRO_BIN="/usr/local/bin/micro"
if ! command -v micro &> /dev/null; then
  MICRO_LATEST_URL=$(curl -s https://api.github.com/repos/zyedidia/micro/releases/latest | grep browser_download_url | grep linux64.tar.gz | cut -d '"' -f 4)
  TMPDIR=$(mktemp -d)
  curl -L "$MICRO_LATEST_URL" -o "$TMPDIR/micro.tar.gz"
  tar -xzf "$TMPDIR/micro.tar.gz" -C "$TMPDIR"
  sudo install "$TMPDIR/micro" "$MICRO_BIN"
  sudo chmod +x "$MICRO_BIN"
  rm -rf "$TMPDIR"
else
  echo "micro already installed, skipping."
fi

# --- Install Docker packages ---
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo ">>> Adding user '$USER_NAME' to docker group (logout/login required)..."
if groups "$USER_NAME" | grep -q '\bdocker\b'; then
  echo "User '$USER_NAME' is already in docker group."
else
  sudo usermod -aG docker "$USER_NAME"
  echo "User '$USER_NAME' added to docker group."
fi

# --- Copy env.bak to .env ---
if [ -f "$HOMESERVER_DIR/etc/env.bak" ]; then
  cp -f "$HOMESERVER_DIR/etc/env.bak" "$HOMESERVER_DIR/.env"
  echo "Copied env.bak to .env, overwriting existing .env if present."
else
  echo "Warning: env.bak not found in $HOMESERVER_DIR. .env file not created."
fi

# --- 9. Fix ownership and setgid bit on HomeServer directory ---
echo ">>> Setting ownership and permissions for $HOMESERVER_DIR..."
sudo chown -R "$USER_NAME":"$USER_NAME" "$HOMESERVER_DIR"
sudo chmod -R u+rwX "$HOMESERVER_DIR"
find "$HOMESERVER_DIR" -type d -exec sudo chmod g+s {} +

echo "Ownership, permissions, and setgid bit set."

# --- 10. Install WireGuard kernel support ---
sudo apt install -y wireguard

if ! lsmod | grep -q wireguard; then
  if ! sudo modprobe wireguard; then
    echo "Warning: WireGuard kernel module failed to load."
  else
    echo "WireGuard module loaded."
  fi
else
  echo "WireGuard module already loaded."
fi

# --- 11. Install WireGuard Manager script ---
WIREGUARD_MANAGER_PATH="/usr/local/bin/wireguard-manager.sh"
sudo curl -fsSL https://raw.githubusercontent.com/complexorganizations/wireguard-manager/main/wireguard-manager.sh -o "$WIREGUARD_MANAGER_PATH"
sudo chmod +x "$WIREGUARD_MANAGER_PATH"

if [[ "${1:-}" == "--wg-manager" ]]; then
  echo ">>> Launching WireGuard Manager (interactive)..."
  bash "$WIREGUARD_MANAGER_PATH"
else
  echo "WireGuard Manager install complete."
  echo "To launch it interactively, run:"
  echo "  sudo bash $WIREGUARD_MANAGER_PATH"
fi

export PATH="$USER_HOME/bin:$PATH"

# --- 12. Final notes ---
echo
echo ">>> Setup complete!"
echo "Remember to log out and back in or reboot to apply docker group permissions."
echo "After that, place your .env file into $HOMESERVER_DIR if needed."
echo "Then run your start-services.sh script from $HOMESERVER_DIR to start your Docker services."

# --- 13. Make start/stop scripts globally accessible ---
if [ -f "$HOMESERVER_DIR/scripts/start-services.sh" ]; then
  sudo ln -sf "$HOMESERVER_DIR/scripts/start-services.sh" /usr/local/bin/start-services
  sudo chmod +x "$HOMESERVER_DIR/scripts/start-services.sh"
  echo "Symlinked start-services.sh to /usr/local/bin/start-services"
fi

if [ -f "$HOMESERVER_DIR/scripts/stop-services.sh" ]; then
  sudo ln -sf "$HOMESERVER_DIR/scripts/stop-services.sh" /usr/local/bin/stop-services
  sudo chmod +x "$HOMESERVER_DIR/scripts/stop-services.sh"
  echo "Symlinked stop-services.sh to /usr/local/bin/stop-services"
fi

sudo adduser "$USER" ssl-cert
echo "startxfce4" > "$USER_HOME/.xsession"

# Create docker networks
docker network create --subnet=172.18.0.0/24 VPN-network || true
docker network create --subnet=172.19.0.0/24 Wireguard-network || true
docker network create --subnet=172.20.0.0/24 HomeServer-network || true

# Make scripts executable
chmod +x /home/homeserver/HomeServer/scripts/generate-service-scripts.sh
chmod +x /home/homeserver/HomeServer/scripts/system-rclone-nightly.sh
chmod +x /home/homeserver/HomeServer/scripts/duckdns.sh
chmod +x /home/homeserver/HomeServer/scripts/watch-wg-ip.sh

# Set up cronjobs
add_cronjob 'system-rclone-nightly.sh' "0 4 * * * /home/homeserver/HomeServer/scripts/system-rclone-nightly.sh >> /home/homeserver/backups/logs/cron/cron.log 2>&1"
add_cronjob 'duckdns.sh' "*/5 * * * * /home/homeserver/HomeServer/scripts/duckdns.sh >/dev/null 2>&1"
add_cronjob 'watch-wg-ip.sh' "*/5 * * * * /home/homeserver/HomeServer/scripts/watch-wg-ip.sh"

sudo cp "$HOMESERVER_DIR/configs/wireguard/wg0.conf" /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo chown root:root /etc/wireguard/wg0.conf

sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

echo
echo ">>> Validating WireGuard service status..."

if sudo systemctl is-active --quiet wg-quick@wg0; then
  echo "WireGuard service wg-quick@wg0 is running."
else
  echo "Warning: WireGuard service wg-quick@wg0 is NOT running!"
  echo "Check /etc/wireguard/wg0.conf and system logs (journalctl -u wg-quick@wg0) for errors."
fi

echo
echo ">>> Setup complete! Please reboot or log out/in to apply docker group and network changes."

exit 0
