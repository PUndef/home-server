#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== resolv.conf ==="
cat /etc/resolv.conf

echo
echo "=== install some probes ==="
sudo apk add curl 2>&1 | tail -3

echo
echo "=== curl https time.cloudflare.com ==="
curl -sI -m 5 https://time.cloudflare.com 2>&1 | head -8

echo
echo "=== udp 123 outbound (raw) ==="
echo "abc" | nc -u -w 3 162.159.200.123 123 2>&1 | head
echo "udp ret: $?"

echo
echo "=== ip rule / route ==="
ip rule
ip route

echo
echo "=== nft / iptables state ==="
sudo nft list ruleset 2>&1 | head -20
sudo iptables -S 2>&1 | head -20'
