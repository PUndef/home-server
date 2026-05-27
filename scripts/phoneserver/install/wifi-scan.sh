#!/bin/bash
# Bring up wlan0 and scan for nearby networks.
PHONE_IP=${PHONE_IP:-172.16.42.1}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'sudo ip link set wlan0 up
    echo === iw dev info ===
    sudo iw dev wlan0 info
    echo
    echo === scan ===
    sudo iw dev wlan0 scan 2>&1 | grep -E "SSID:|signal:|^BSS" | head -60'
