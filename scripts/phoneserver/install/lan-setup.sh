#!/bin/bash
# After eth0 has DHCP (USB-Ethernet hub -> LAN switch):
#   - dhcpcd in default runlevel
#   - chrony NTP
#   - public DNS in /etc/resolv.conf (not router dnsmasq / sing-box fake-IP)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../phone-defaults.sh
source "${SCRIPT_DIR}/../phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo === dhcpcd persistent ===
sudo rc-update add dhcpcd default 2>&1
sudo rc-service dhcpcd start 2>&1 | tail -3
echo
echo === resize root ===
df -h / | head -2
sudo resize2fs /dev/sda18 2>&1 | tail -3
df -h / | head -2
echo
echo === chrony ===
sudo rc-update add chronyd default 2>&1 || true
sudo rc-service chronyd start 2>&1 | tail -3
sleep 2
sudo chronyc -a makestep 2>&1 | tail -3
date
echo
echo === replace resolv.conf with public DNS ===
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
echo "nameserver 8.8.8.8" | sudo tee -a /etc/resolv.conf
cat /etc/resolv.conf
echo
echo === summary ===
hostname; uname -r; uptime
ip -4 addr show eth0 | grep inet
ping -c 2 -W 2 1.1.1.1 | tail -2'
