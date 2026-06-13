#!/bin/bash
# Share WSL's internet with phoneserver over the USB-net link.
#
# Why: during initial install before eth0 has LAN DHCP, the only way to
# `apk update` from pmOS is through the WSL uplink. We MASQUERADE on the
# WSL side and add a default route + DNS on the phone side.
#
# All rules use plain iptables (Ubuntu 24.04 ships `iptables-nft`).
# Survives until WSL VM reboots; re-run as needed.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/phone-defaults.sh"
SUDO_PASS=${SUDO_PASS:-changemenow}    # initial user sudo password
IFACE_WAN=${IFACE_WAN:-eth0}

IFACE_USB=$(ip -4 link show | grep -oP 'enx[a-f0-9]+' | head -1)
if [ -z "$IFACE_USB" ]; then
    echo "ERROR: no USB-cdc interface in WSL."
    exit 1
fi

echo "USB iface: $IFACE_USB"
echo "WAN iface: $IFACE_WAN"

sudo sysctl -w net.ipv4.ip_forward=1 >/dev/null

sudo iptables -t nat -C POSTROUTING -o "$IFACE_WAN" -j MASQUERADE 2>/dev/null \
    || sudo iptables -t nat -A POSTROUTING -o "$IFACE_WAN" -j MASQUERADE
sudo iptables -C FORWARD -i "$IFACE_USB" -o "$IFACE_WAN" -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$IFACE_USB" -o "$IFACE_WAN" -j ACCEPT
sudo iptables -C FORWARD -i "$IFACE_WAN" -o "$IFACE_USB" \
    -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null \
    || sudo iptables -A FORWARD -i "$IFACE_WAN" -o "$IFACE_USB" \
        -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "=== applying default route + DNS on phone ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "${SSH_REMOTE}" \
    "echo '$SUDO_PASS' | sudo -S sh -c '
        ip route del default 2>/dev/null || true
        ip route add default via 172.16.42.2
        printf \"nameserver 1.1.1.1\nnameserver 8.8.8.8\n\" > /etc/resolv.conf
    '
    echo === route ===
    ip route
    echo === ping ===
    ping -c 2 -W 2 1.1.1.1 | tail -3"
