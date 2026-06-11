#!/bin/bash
# Install Docker (if missing) and start HA + Wyoming stack on phoneserver.
# Run from WSL: PHONE_IP=192.168.1.227 ./scripts/phoneserver/install-homeassistant.sh
# Does not touch OpenWrt.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/phone-defaults.sh"

REMOTE_DIR=/opt/homeassistant
SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")

echo "[install-ha] target pmos@${PHONE_IP}"

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" "sudo mkdir -p ${REMOTE_DIR}/config && sudo chown -R pmos:pmos ${REMOTE_DIR}"

scp "${SSH_OPTS[@]}" "${SCRIPT_DIR}/homeassistant/compose.yaml" "pmos@${PHONE_IP}:${REMOTE_DIR}/compose.yaml"

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" sh -s <<'REMOTE'
set -eu
REMOTE_DIR=/opt/homeassistant

if ! command -v docker >/dev/null 2>&1; then
  echo "[install-ha] installing docker..."
  sudo apk add --no-cache docker docker-cli-compose docker-openrc
  sudo rc-update add docker boot 2>/dev/null || true
fi

# pmOS kernel may lack iptables NAT modules; host-network stacks work without it.
if [ ! -f /etc/docker/daemon.json ]; then
  sudo mkdir -p /etc/docker
  printf '%s\n' '{"iptables": false, "ip6tables": false}' | sudo tee /etc/docker/daemon.json >/dev/null
fi

if ! sudo rc-service docker status 2>/dev/null | grep -q started; then
  sudo rc-service docker start
  sleep 5
fi

if ! sudo rc-service docker status 2>/dev/null | grep -q started; then
  sudo rc-service docker start
  sleep 2
fi

sudo docker info >/dev/null
echo "[install-ha] docker ok"

cd "$REMOTE_DIR"
# pmos in docker group avoids sudo on every compose command
sudo addgroup pmos docker 2>/dev/null || true
sudo docker compose pull
sudo docker compose up -d

echo "[install-ha] containers:"
sudo docker compose ps

echo ""
echo "HA UI: http://$(hostname -I 2>/dev/null | awk '{print $1}'):8123"
echo "Voice stack: see docs/phoneserver/voice-assistant.md (Yandex + Groq cloud)"
REMOTE

echo "[install-ha] done"
