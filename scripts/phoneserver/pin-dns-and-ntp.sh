#!/bin/bash
# Make /etc/resolv.conf survive dhcpcd renews and force NTP step.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "${SSH_REMOTE}" \
    'echo "=== dhcpcd nohook resolv.conf ==="
if ! sudo grep -q "^nohook resolv.conf" /etc/dhcpcd.conf; then
    echo "nohook resolv.conf" | sudo tee -a /etc/dhcpcd.conf
fi
sudo tail -3 /etc/dhcpcd.conf
echo
echo "=== rewrite resolv.conf ==="
sudo sh -c "printf \"nameserver 1.1.1.1\nnameserver 8.8.8.8\n\" > /etc/resolv.conf"
cat /etc/resolv.conf
echo
echo "=== force NTP step ==="
sudo rc-service chronyd restart 2>/dev/null || sudo systemctl restart chronyd 2>/dev/null || true
sleep 3
sudo chronyc -a makestep
sleep 2
date'
