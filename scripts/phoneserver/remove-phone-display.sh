#!/usr/bin/env bash
# Stop LCD status service and remove files from phoneserver.
# Usage: ./remove-phone-display.sh

set -euo pipefail

PHONE_IP="${PHONE_IP:-192.168.1.116}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
SSH=(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}")
REMOTE="pmos@${PHONE_IP}"

if [[ ! -f "${SSH_KEY}" ]]; then
    echo "missing SSH key: ${SSH_KEY}" >&2
    exit 1
fi

echo "=== remove phoneserver LCD status (${PHONE_IP}) ==="
"${SSH[@]}" "${REMOTE}" 'sudo sh -s' <<'REMOTE'
set -eu
rc-service phoneserver-display stop 2>/dev/null || true
rc-update del phoneserver-display default 2>/dev/null || true
rm -f /etc/init.d/phoneserver-display
rm -f /etc/conf.d/phoneserver-display
rm -f /opt/phoneserver/phone-display-loop.sh
rm -f /opt/phoneserver/term-status-lcd.sh
# Clear status text from LCD; keep backlight on (do not set brightness to 0)
if [ -w /sys/class/backlight/backlight/brightness ]; then
    max=$(cat /sys/class/backlight/backlight/max_brightness 2>/dev/null || echo 4095)
    echo "$max" > /sys/class/backlight/backlight/brightness 2>/dev/null \
        || echo 4000 > /sys/class/backlight/backlight/brightness
fi
printf '\033[2J\033[H' > /dev/tty1 2>/dev/null || true
echo "phoneserver-display removed"
REMOTE
echo "done"
