#!/usr/bin/env bash
set -Eeuo pipefail

APP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_NAME="evm-v3"
PYTHON_BIN="python3"

if [[ $EUID -ne 0 ]]; then
  echo "Please run this installer as root:"
  echo "sudo bash install.sh"
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer currently supports Ubuntu/Debian (apt)."
  exit 1
fi

echo "======================================"
echo "        EVM-V3 BOT INSTALLER"
echo "======================================"
echo "Install directory: ${APP_DIR}"
echo

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip ca-certificates curl

if [[ ! -f "${APP_DIR}/EVM-V3-bot.py" && ! -f "${APP_DIR}/bot.py" ]]; then
  echo "ERROR: EVM-V3-bot.py or bot.py was not found in ${APP_DIR}"
  echo "Upload the bot file and install.sh into the same directory."
  exit 1
fi

if [[ -f "${APP_DIR}/EVM-V3-bot.py" ]]; then
  cp -f "${APP_DIR}/EVM-V3-bot.py" "${APP_DIR}/bot.py"
fi

if [[ ! -f "${APP_DIR}/.env" ]]; then
  if [[ -f "${APP_DIR}/.env.example" ]]; then
    cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
    chmod 600 "${APP_DIR}/.env"
    echo "Created .env from .env.example"
  else
    cat > "${APP_DIR}/.env" <<'ENVEOF'
DISCORD_TOKEN=
BOT_NAME=EVM-V3
BOT_VERSION=3
BOT_PREFIX=$
MAIN_ADMIN_ID=
VPS_USER_ROLE_ID=0
PUBLIC_IPV4=
AUTO_DETECT_PUBLIC_IP=true
DEFAULT_STORAGE_POOL=default
NODE_DEFAULT_SLOTS=100
VPS_PRIVILEGED=false
VPS_NESTING=true
KVM_PINGGY_ENABLED=true
ENVEOF
    chmod 600 "${APP_DIR}/.env"
    echo "Created a blank .env file"
  fi
else
  echo "Existing .env found; leaving it unchanged."
fi

python3 -m venv "${APP_DIR}/venv"
"${APP_DIR}/venv/bin/python" -m pip install --upgrade pip wheel
"${APP_DIR}/venv/bin/python" -m pip install discord.py python-dotenv requests psutil Pillow

# Ask for required settings without displaying the Discord token.
read -r -p "Discord Bot Token (press Enter to keep current .env value): " -s BOT_TOKEN
echo
read -r -p "Main Admin Discord User ID (press Enter to keep current .env value): " ADMIN_ID

APP_DIR="${APP_DIR}" BOT_TOKEN="${BOT_TOKEN}" ADMIN_ID="${ADMIN_ID}" python3 - <<'PY'
import os
from pathlib import Path

env_path = Path(os.environ["APP_DIR"]) / ".env"
lines = env_path.read_text().splitlines() if env_path.exists() else []
values = {
    "DISCORD_TOKEN": os.environ.get("BOT_TOKEN", ""),
    "MAIN_ADMIN_ID": os.environ.get("ADMIN_ID", ""),
}
for key, value in values.items():
    if not value:
        continue
    replacement = f"{key}={value}"
    found = False
    for i, line in enumerate(lines):
        if line.strip().startswith(key + "="):
            lines[i] = replacement
            found = True
            break
    if not found:
        lines.append(replacement)
env_path.write_text("\n".join(lines) + "\n")
env_path.chmod(0o600)
PY

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<UNIT
[Unit]
Description=EVM-V3 Discord VPS Bot
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
WorkingDirectory=${APP_DIR}
ExecStart=${APP_DIR}/venv/bin/python ${APP_DIR}/bot.py
Restart=always
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

echo
echo "Installation files and Python dependencies are ready."
if grep -Eq '^DISCORD_TOKEN=($|PUT_YOUR_DISCORD_BOT_TOKEN_HERE)' "${APP_DIR}/.env"; then
  echo "WARNING: Add a valid DISCORD_TOKEN to ${APP_DIR}/.env before starting the bot."
  echo "Edit it with: nano ${APP_DIR}/.env"
  echo "Then start with: systemctl start ${SERVICE_NAME}"
else
  systemctl restart "${SERVICE_NAME}" || systemctl start "${SERVICE_NAME}"
  echo "Bot service started."
fi

echo
echo "Useful commands:"
echo "  systemctl status ${SERVICE_NAME}"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo "  systemctl restart ${SERVICE_NAME}"
echo "  systemctl stop ${SERVICE_NAME}"
echo
echo "Note: This script installs the bot runtime only. Configure LXD/Incus or your KVM/Proxmox backend separately."
