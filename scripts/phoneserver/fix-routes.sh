#!/bin/bash
# Remove the stale default route via the WSL USB-net link so the phone uses
# the wlan0 default via the LAN gateway. Also drop the duplicate secondary
# IP added by a stray dhcpcd request, and lock /etc/resolv.conf with .head.
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== routes before ==="
ip route
echo
echo "=== fixes ==="
# kill default via WSL
sudo ip route del default via 172.16.42.2 dev usb0 2>&1 || true
# drop secondary address
sudo ip addr del 192.168.1.117/24 dev wlan0 2>&1 || true
# drop the duplicate default
sudo ip route del default via 192.168.1.1 dev wlan0 metric 3004 2>&1 || true
echo
echo "=== routes after ==="
ip route
echo
echo "=== resolv ==="
sudo sh -c "printf '\''nameserver 1.1.1.1\nnameserver 8.8.8.8\n'\'' > /etc/resolv.conf"
cat /etc/resolv.conf
echo
echo "=== ping ==="
ping -c 3 -W 2 1.1.1.1 | tail -4'
