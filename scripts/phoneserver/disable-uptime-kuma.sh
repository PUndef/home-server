#!/usr/bin/env bash
# Stop and disable Uptime Kuma on phoneserver (pkill — rc-service stop often hangs).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

SSH=(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 -o ServerAliveInterval=10 -o ServerAliveCountMax=2 -i "${SSH_KEY}")
REMOTE="pmos@${PHONE_IP}"

echo "=== disable uptime-kuma on phoneserver (${PHONE_IP}) ==="
"${SSH[@]}" "${REMOTE}" \
  "sudo pkill -f /opt/uptime-kuma/server/server.js 2>/dev/null || true; \
   sudo rc-update del uptime-kuma default 2>/dev/null || true; \
   pgrep -af uptime-kuma || echo stopped"

echo "done"
