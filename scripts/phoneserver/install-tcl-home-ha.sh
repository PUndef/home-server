#!/bin/bash
# Install TCL Home (unofficial) custom integration for Home Assistant (Container).
# Run from WSL: PHONE_IP=192.168.50.127 bash scripts/phoneserver/install-tcl-home-ha.sh
#
# After restart: HA UI → Настройки → Устройства и службы → + → TCL Home → TCL Home credentials

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/phone-defaults.sh"

REMOTE_CONFIG=/opt/homeassistant/config
SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")
REPO_ZIP=https://github.com/nemesa/ha-tcl-home-unofficial-integration/archive/refs/heads/main.zip

echo "[tcl-home-ha] target ${SSH_REMOTE}"

ssh "${SSH_OPTS[@]}" "${SSH_REMOTE}" sh -s <<REMOTE
set -eu
REMOTE_CONFIG=${REMOTE_CONFIG}
REPO_ZIP=${REPO_ZIP}

sudo mkdir -p "\${REMOTE_CONFIG}/custom_components"
cd /tmp
rm -rf ha-tcl-home-unofficial-integration-main tcl-home.zip
wget -q -O tcl-home.zip "\${REPO_ZIP}" || curl -fsSL -o tcl-home.zip "\${REPO_ZIP}"
unzip -q -o tcl-home.zip
sudo rm -rf "\${REMOTE_CONFIG}/custom_components/tcl_home_unofficial"
sudo cp -r ha-tcl-home-unofficial-integration-main/custom_components/tcl_home_unofficial "\${REMOTE_CONFIG}/custom_components/"
sudo chown -R ${SSH_USER}:${SSH_USER} "\${REMOTE_CONFIG}/custom_components"
rm -rf ha-tcl-home-unofficial-integration-main tcl-home.zip
echo "[tcl-home-ha] installed custom_components/tcl_home_unofficial"
REMOTE

ssh "${SSH_OPTS[@]}" "${SSH_REMOTE}" "cd /opt/homeassistant && sudo docker compose restart homeassistant"
echo "[tcl-home-ha] homeassistant restarted"
echo "[tcl-home-ha] next: add integration in UI with TCL Home account (same as mobile app)"
