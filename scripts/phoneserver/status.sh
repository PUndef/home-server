#!/bin/bash
# Quick status snapshot of phoneserver over SSH.

PHONE_IP=${PHONE_IP:-172.16.42.1}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== identity ==="
hostname; uname -r; uptime
echo
echo "=== disk ==="
df -h / /boot | head -3
echo
echo "=== memory ==="
free -h | head -3
echo
echo "=== mounts ==="
mount | grep -E "^/dev/sd"
echo
echo "=== net ==="
ls /sys/class/net/
ip -4 addr show usb0 2>/dev/null | tail -2
ip -4 addr show wlan0 2>/dev/null | tail -2
echo
echo "=== internet ==="
ping -c 1 -W 2 1.1.1.1 2>&1 | tail -2'
