#!/bin/bash
# Fix Beszel agent on phoneserver after network migration (systemd, no phoneserver-wifi).
# Run from WSL: ./fix-beszel-agent-lan.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

echo "=== fix beszel-agent on ${SSH_REMOTE} ==="

ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "${SSH_REMOTE}" "
set -eu
if systemctl cat beszel-agent >/dev/null 2>&1; then
  sudo systemctl restart beszel-agent
  sleep 3
  systemctl is-active beszel-agent || true
  sudo journalctl -u beszel-agent --no-pager -n 15 || true
fi
curl -sS -m 6 -o /dev/null -w 'hub_http=%{http_code}\n' http://192.168.50.35/beszel/ || true
"

echo "done — check https://apps-pundef.mooo.com/beszel/"
