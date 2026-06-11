#!/bin/bash
# Install Groq Cloud API custom integration for Home Assistant (Container).
# Run from WSL: PHONE_IP=192.168.1.227 bash scripts/phoneserver/install-groq-ha.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/phone-defaults.sh"

REMOTE_CONFIG=/opt/homeassistant/config
SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")
REPO_ZIP=https://github.com/HunorLaczko/ha-groq-cloud-api/archive/refs/heads/master.zip

echo "[groq-ha] target pmos@${PHONE_IP}"

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" sh -s <<REMOTE
set -eu
REMOTE_CONFIG=${REMOTE_CONFIG}
REPO_ZIP=${REPO_ZIP}

sudo mkdir -p "\${REMOTE_CONFIG}/custom_components"
cd /tmp
rm -rf ha-groq-cloud-api-master groq.zip
wget -q -O groq.zip "\${REPO_ZIP}" || curl -fsSL -o groq.zip "\${REPO_ZIP}"
unzip -q -o groq.zip
sudo rm -rf "\${REMOTE_CONFIG}/custom_components/groq_cloud_api"
sudo cp -r ha-groq-cloud-api-master/custom_components/groq_cloud_api "\${REMOTE_CONFIG}/custom_components/"
sudo chown -R pmos:pmos "\${REMOTE_CONFIG}/custom_components"
rm -rf ha-groq-cloud-api-master groq.zip
echo "[groq-ha] installed custom_components/groq_cloud_api"
REMOTE

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" "cd /opt/homeassistant && sudo docker compose restart homeassistant"
echo "[groq-ha] homeassistant restarted — add integration in UI"
