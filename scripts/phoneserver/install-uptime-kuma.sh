#!/usr/bin/env bash
# WSL/Linux orchestrator: install Uptime Kuma on phoneserver.
#
# Usage:
#   ./install-uptime-kuma.sh
#   PHONE_IP=192.168.1.116 ./install-uptime-kuma.sh
#   PHONE_IP=172.16.42.1 ./install-uptime-kuma.sh   # USB after wsl-usbnet-up.sh

set -euo pipefail

PHONE_IP="${PHONE_IP:-192.168.1.116}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
KUMA_VERSION="${KUMA_VERSION:-2.3.2}"
KUMA_PORT="${KUMA_PORT:-3001}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "missing SSH key: ${SSH_KEY}" >&2
    echo "run setup-ssh-key.sh first, or set SSH_KEY=..." >&2
    exit 1
fi

SSH=(ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -o ServerAliveCountMax=120 -i "${SSH_KEY}")
SCP=(scp -o StrictHostKeyChecking=no -i "${SSH_KEY}")
REMOTE="pmos@${PHONE_IP}"

echo "=== phoneserver Uptime Kuma (${PHONE_IP}) ==="
if ! "${SSH[@]}" "${REMOTE}" "echo ok" >/dev/null 2>&1; then
    echo "SSH to ${REMOTE} failed." >&2
    echo "  Wi-Fi: PHONE_IP=192.168.1.116 ./install-uptime-kuma.sh" >&2
    echo "  USB:   wsl-usbnet-up.sh then PHONE_IP=172.16.42.1 ./install-uptime-kuma.sh" >&2
    exit 1
fi

"${SCP[@]}" "${REPO_ROOT}/scripts/phoneserver/uptime-kuma-install.sh" "${REMOTE}:/tmp/"
"${SSH[@]}" "${REMOTE}" "chmod 755 /tmp/uptime-kuma-install.sh; sudo env KUMA_VERSION='${KUMA_VERSION}' KUMA_PORT='${KUMA_PORT}' /tmp/uptime-kuma-install.sh"

echo ""
echo "done — open http://${PHONE_IP}:${KUMA_PORT}/ and create admin account"
echo "log on phone: /var/log/uptime-kuma-install.log and /var/log/uptime-kuma.log"
