#!/bin/bash
# Make /etc/resolv.conf survive dhcpcd renews and force NTP step.
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
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
sudo rc-service chronyd restart
sleep 3
sudo chronyc -a makestep
sleep 2
date'
