#!/usr/bin/env bash
# WSL/Linux: install phoneserver-wifi OpenRC service (autostart on boot).
#
# Usage:
#   ./install-wifi-autostart.sh
#   PHONE_IP=192.168.1.116 ./install-wifi-autostart.sh

set -euo pipefail

PHONE_IP="${PHONE_IP:-192.168.1.116}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "missing SSH key: ${SSH_KEY}" >&2
    exit 1
fi

SSH=(ssh -o StrictHostKeyChecking=no -o ServerAliveInterval=30 -i "${SSH_KEY}")
SCP=(scp -o StrictHostKeyChecking=no -i "${SSH_KEY}")
REMOTE="pmos@${PHONE_IP}"

echo "=== phoneserver Wi-Fi autostart (${PHONE_IP}) ==="
if ! "${SSH[@]}" "${REMOTE}" "echo ok" >/dev/null 2>&1; then
    echo "SSH to ${REMOTE} failed." >&2
    echo "  USB: wsl-usbnet-up.sh then PHONE_IP=172.16.42.1 ./install-wifi-autostart.sh" >&2
    exit 1
fi

"${SCP[@]}" \
    "${REPO_ROOT}/scripts/phoneserver/phoneserver-wifi.initd" \
    "${REPO_ROOT}/scripts/phoneserver/phoneserver-wifi-install.sh" \
    "${REMOTE}:/tmp/"

"${SSH[@]}" "${REMOTE}" \
    "chmod 755 /tmp/phoneserver-wifi.initd /tmp/phoneserver-wifi-install.sh; \
     sudo PHONESERVER_WIFI_INIT=/tmp/phoneserver-wifi.initd /tmp/phoneserver-wifi-install.sh"

echo ""
echo "done — reboot phone to test: Wi-Fi should come up without USB"
echo "log: /var/log/phoneserver-wifi.log"
