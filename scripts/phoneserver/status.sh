#!/bin/bash
# Quick status snapshot of phoneserver over SSH.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "${SSH_REMOTE}" \
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
ip -4 addr show eth0 2>/dev/null | tail -2
ip -4 addr show usb0 2>/dev/null | tail -2
echo
echo "=== internet ==="
ping -c 1 -W 2 1.1.1.1 2>&1 | tail -2'
