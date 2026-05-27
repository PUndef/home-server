#!/bin/bash
# Reconnect wlan0 after reboot (wpa_supplicant + dhcpcd already configured).
# Use over USB when Wi-Fi IP is unreachable:
#   ./wsl-usbnet-up.sh
#   PHONE_IP=172.16.42.1 ./wifi-reconnect.sh
#
# Over Wi-Fi once it works:
#   PHONE_IP=192.168.1.116 ./wifi-reconnect.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${SSH_KEY}" "pmos@${PHONE_IP}" \
    'sudo sh -s' <<'REMOTE'
set -eu
echo "=== wlan0 link ==="
ip link set wlan0 up 2>/dev/null || true
ip link show wlan0 | head -2

if [ ! -f /etc/wpa_supplicant/wpa_supplicant.conf ]; then
    echo "ERROR: missing /etc/wpa_supplicant/wpa_supplicant.conf — run wifi-connect.sh first" >&2
    exit 1
fi
ln -sf wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-wlan0.conf 2>/dev/null || true

echo "=== wpa_supplicant ==="
rc-service wpa_supplicant stop 2>/dev/null || killall wpa_supplicant 2>/dev/null || true
sleep 1
rc-update add wpa_supplicant default 2>/dev/null || true
rc-service wpa_supplicant start 2>&1 || wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211
sleep 4

echo "=== dhcpcd ==="
rc-update add dhcpcd default 2>/dev/null || true
rc-service dhcpcd restart 2>&1 || dhcpcd -t 30 -L wlan0
sleep 3

echo "=== addresses ==="
ip -4 addr show wlan0
ip route | head -5

echo "=== wpa_cli (if running) ==="
wpa_cli -i wlan0 status 2>/dev/null | grep -E 'wpa_state|ssid|ip_address' || true

echo "=== ping ==="
ping -c 2 -W 3 -I wlan0 192.168.50.35 2>&1 | tail -3 || true
ping -c 2 -W 3 -I wlan0 1.1.1.1 2>&1 | tail -3 || true

echo "=== beszel-agent ==="
rc-service beszel-agent restart 2>/dev/null || true
sleep 2
rc-service beszel-agent status 2>&1 || true
tail -5 /var/log/beszel-agent.log 2>/dev/null || true
REMOTE

echo "done — try: ssh pmos@$(ssh ... ip) or ping new wlan0 IP from router"
