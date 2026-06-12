#!/bin/bash
# Fix Beszel agent on phoneserver after LAN migration (no phoneserver-wifi).
# Run from WSL: PHONE_IP=192.168.1.227 ./fix-beszel-agent-lan.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

REMOTE="pmos@${PHONE_IP}"
INIT="/etc/init.d/beszel-agent"

echo "=== fix beszel-agent on ${PHONE_IP} ==="

ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "${REMOTE}" "
set -eu
if [ -f '${INIT}' ]; then
  sudo sed -i '/phoneserver-wifi/d' '${INIT}'
  sudo sed -i 's/need phoneserver-wifi net/need net/' '${INIT}' 2>/dev/null || true
  sudo sed -i 's/after phoneserver-wifi//' '${INIT}' 2>/dev/null || true
fi
sudo rc-update del phoneserver-wifi default 2>/dev/null || true
sudo rc-service phoneserver-wifi stop 2>/dev/null || true
sudo rc-service beszel-agent restart
sleep 3
sudo rc-service beszel-agent status || true
echo '--- log ---'
sudo tail -15 /var/log/beszel-agent.log 2>/dev/null || true
curl -sS -m 6 -o /dev/null -w 'hub_http=%{http_code}\n' http://192.168.50.35/beszel/ || true
"

echo "done — check https://apps-pundef.mooo.com/beszel/"
