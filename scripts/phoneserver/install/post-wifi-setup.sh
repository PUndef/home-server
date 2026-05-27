#!/bin/bash
# After wifi is connected and DHCP got an IP:
#   - make dhcpcd persistent in default runlevel
#   - resize root fs to the full userdata partition
#   - configure chrony, force time sync
#   - drop a DNS-via-public-resolvers /etc/resolv.conf override (we don't
#     want OpenWrt's dnsmasq with sing-box fake-IP for phoneserver)
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo === dhcpcd persistent ===
sudo rc-update add dhcpcd default 2>&1
sudo rc-service dhcpcd start 2>&1 | tail -3
echo
echo === wpa_supplicant per-interface ===
sudo rc-update add wpa_supplicant default 2>&1 || true
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
ip -4 addr show wlan0 | grep inet
ping -c 2 -W 2 1.1.1.1 | tail -2'
