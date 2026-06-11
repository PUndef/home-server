#!/bin/bash
# Install Yandex SpeechKit custom integration for Home Assistant (Container).
# Run from WSL: PHONE_IP=192.168.1.227 bash scripts/phoneserver/install-yandex-speechkit-ha.sh
#
# After restart: HA UI → Настройки → Устройства и службы → + → Yandex SpeechKit → API key

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/phone-defaults.sh"

REMOTE_CONFIG=/opt/homeassistant/config
SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")
REPO_ZIP=https://github.com/black-roland/homeassistant-yandex-speechkit/archive/refs/heads/master.zip

echo "[yandex-sk] target pmos@${PHONE_IP}"

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" sh -s <<REMOTE
set -eu
REMOTE_CONFIG=${REMOTE_CONFIG}
REPO_ZIP=${REPO_ZIP}

sudo mkdir -p "\${REMOTE_CONFIG}/custom_components"
cd /tmp
rm -rf homeassistant-yandex-speechkit-master yandex-sk.zip
wget -q -O yandex-sk.zip "\${REPO_ZIP}" || curl -fsSL -o yandex-sk.zip "\${REPO_ZIP}"
unzip -q -o yandex-sk.zip
sudo rm -rf "\${REMOTE_CONFIG}/custom_components/yandex_speechkit"
sudo cp -r homeassistant-yandex-speechkit-master/custom_components/yandex_speechkit "\${REMOTE_CONFIG}/custom_components/"
sudo chown -R pmos:pmos "\${REMOTE_CONFIG}/custom_components"
rm -rf homeassistant-yandex-speechkit-master yandex-sk.zip
echo "[yandex-sk] installed custom_components/yandex_speechkit"
REMOTE

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" "cd /opt/homeassistant && sudo docker compose restart homeassistant"
echo "[yandex-sk] homeassistant restarted"
echo "[yandex-sk] next: add integration in UI with Yandex Cloud API key"
