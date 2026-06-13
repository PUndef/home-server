#!/bin/bash
# Install Docker (if missing) and start HA stack on phoneserver (v25.12 / systemd).
# Run from WSL: PHONE_IP=192.168.50.127 ./scripts/phoneserver/install-homeassistant.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/phone-defaults.sh"

REMOTE_DIR=/opt/homeassistant
SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")

echo "[install-ha] target ${SSH_REMOTE}"

ssh "${SSH_OPTS[@]}" "${SSH_REMOTE}" "sudo mkdir -p ${REMOTE_DIR}/config && sudo chown -R ${SSH_USER}:${SSH_USER} ${REMOTE_DIR}"

scp "${SSH_OPTS[@]}" "${SCRIPT_DIR}/homeassistant/compose.yaml" "${SSH_REMOTE}:${REMOTE_DIR}/compose.yaml"

ssh "${SSH_OPTS[@]}" "${SSH_REMOTE}" sh -s <<REMOTE
set -eu
REMOTE_DIR=/opt/homeassistant
SSH_USER=${SSH_USER}

if ! command -v docker >/dev/null 2>&1; then
  echo "[install-ha] installing docker..."
  sudo apk add --no-cache docker docker-cli-compose
  sudo rc-update add docker boot 2>/dev/null || sudo systemctl enable docker 2>/dev/null || true
fi

if [ ! -f /etc/docker/daemon.json ]; then
  sudo mkdir -p /etc/docker
  printf '%s\n' '{"iptables": false, "ip6tables": false}' | sudo tee /etc/docker/daemon.json >/dev/null
fi

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl start docker 2>/dev/null || true
else
  sudo rc-service docker start 2>/dev/null || true
fi
sleep 3
sudo docker info >/dev/null
echo "[install-ha] docker ok"

HA_NFT=/etc/nftables.d/52_homeassistant.nft
if [ ! -f "\$HA_NFT" ]; then
  sudo tee "\$HA_NFT" >/dev/null <<'NFT'
#!/usr/sbin/nft -f
table inet filter {
	chain input {
		iifname "wlan*" tcp dport 8123 accept comment "Home Assistant UI on wlan"
		iifname "eth*" tcp dport 8123 accept comment "Home Assistant UI on eth"
	}
}
NFT
  sudo rc-service nftables reload 2>/dev/null || sudo systemctl reload nftables 2>/dev/null || sudo nft -f /etc/nftables.nft
  echo "[install-ha] opened tcp/8123 in nftables"
fi

cd "\$REMOTE_DIR"
sudo addgroup "\$SSH_USER" docker 2>/dev/null || true
sudo docker compose pull
sudo docker compose up -d

echo "[install-ha] containers:"
sudo docker compose ps

echo ""
echo "HA UI: http://\$(hostname -I 2>/dev/null | awk '{print \$1}'):8123"
echo "Voice stack: see docs/phoneserver/voice-assistant.md (Yandex + Groq cloud)"
REMOTE

echo "[install-ha] done"
