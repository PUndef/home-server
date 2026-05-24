#!/usr/bin/env bash
# Enable status text on the phone's physical screen (ui=none → no UI by default).
# Usage: ./install-phone-display.sh
#   PHONE_IP=192.168.1.116 ./install-phone-display.sh

set -euo pipefail

PHONE_IP="${PHONE_IP:-192.168.1.116}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SSH=(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}")
SCP=(scp -o StrictHostKeyChecking=no -i "${SSH_KEY}")
REMOTE="pmos@${PHONE_IP}"

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "missing SSH key: ${SSH_KEY}" >&2
    exit 1
fi

echo "=== phoneserver LCD status (${PHONE_IP}) ==="
"${SSH[@]}" "${REMOTE}" "sudo mkdir -p /opt/phoneserver"

"${SCP[@]}" \
    "${SCRIPT_DIR}/term-status.sh" \
    "${SCRIPT_DIR}/term-status-lcd.sh" \
    "${SCRIPT_DIR}/phone-display-loop.sh" \
    "${SCRIPT_DIR}/phoneserver-display.initd" \
    "${SCRIPT_DIR}/phoneserver-display.confd" \
    "${REMOTE}:/tmp/"

"${SSH[@]}" "${REMOTE}" 'sudo sh -s' <<'REMOTE'
set -eu
apk add --no-cache font-terminus kbd 2>/dev/null || true
install -m755 /tmp/term-status.sh /opt/phoneserver/term-status.sh
install -m755 /tmp/term-status-lcd.sh /opt/phoneserver/term-status-lcd.sh
install -m755 /tmp/phone-display-loop.sh /opt/phoneserver/phone-display-loop.sh
install -m755 /tmp/phoneserver-display.initd /etc/init.d/phoneserver-display
install -m644 /tmp/phoneserver-display.confd /etc/conf.d/phoneserver-display
rc-update add phoneserver-display default 2>/dev/null || true
rc-service phoneserver-display restart
sleep 1
rc-service phoneserver-display status || true
echo "Backlight off after LCD_IDLE_SEC (see /etc/conf.d/phoneserver-display)."
REMOTE

echo "done"
