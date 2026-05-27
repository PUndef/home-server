#!/bin/bash
# Bring up wlan0 and scan for nearby networks.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/../phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'sudo ip link set wlan0 up
    echo === iw dev info ===
    sudo iw dev wlan0 info
    echo
    echo === scan ===
    sudo iw dev wlan0 scan 2>&1 | grep -E "SSID:|signal:|^BSS" | head -60'
