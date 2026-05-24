#!/bin/sh
# Turn phone LCD backlight back on (e.g. after remove-phone-display left it at 0).
# Local: sudo ./wake-display.sh
# Remote: PHONE_IP=192.168.1.116 ./scripts/phoneserver/wake-display.sh remote

set -eu

wake() {
    BL=/sys/class/backlight/backlight
    [ -w "$BL/brightness" ] || { echo "no backlight control"; exit 1; }
    max=$(cat "$BL/max_brightness" 2>/dev/null || echo 4095)
    echo "$max" > "$BL/brightness" 2>/dev/null || echo 4000 > "$BL/brightness"
    chvt 1 2>/dev/null || true
    printf 'brightness=%s\n' "$(cat "$BL/brightness")"
}

if [ "${1:-}" = "remote" ]; then
    PHONE_IP="${PHONE_IP:-192.168.1.116}"
    SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
    exec ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "pmos@${PHONE_IP}" \
        "sudo sh -c 'BL=/sys/class/backlight/backlight; max=\$(cat \$BL/max_brightness 2>/dev/null || echo 4095); echo \$max > \$BL/brightness; chvt 1 2>/dev/null; cat \$BL/brightness'"
    exit 0
fi

wake
