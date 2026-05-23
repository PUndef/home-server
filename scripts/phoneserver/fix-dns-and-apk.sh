#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'sudo killall apk 2>/dev/null || true
sudo killall wget 2>/dev/null || true
echo "=== rewrite resolv.conf ==="
sudo sh -c "printf '\''nameserver 1.1.1.1\nnameserver 8.8.8.8\n'\'' > /etc/resolv.conf"
# also lock it from dhcpcd (chmod immutable does not work in some pmOS;
# easier path: write resolv.conf.head which dhcpcd-hooks respect)
sudo sh -c "printf '\''nameserver 1.1.1.1\nnameserver 8.8.8.8\n'\'' > /etc/resolv.conf.head"
cat /etc/resolv.conf
echo
echo "=== quick connectivity ==="
ping -c 2 -W 2 1.1.1.1 | tail -2
echo
echo "=== try curl ==="
which curl || sudo apk add curl 2>&1 | tail -3
curl -m 5 -sI https://time.cloudflare.com | head -3'
