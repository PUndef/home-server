#!/bin/bash
# Remove llama.cpp, models, and llama-server service from phoneserver.
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'set -e
sudo rc-service llama-server stop 2>/dev/null || true
sudo rc-update del llama-server default 2>/dev/null || true
sudo rm -f /etc/init.d/llama-server /var/log/llama-server.log /run/llama-server.pid
rm -rf ~/llama.cpp ~/models
echo "=== disk freed ==="
df -h ~ | tail -1
echo "=== port 8080 ==="
ss -tln | grep 8080 || echo free
ls ~/llama.cpp 2>/dev/null || echo no llama.cpp
ls ~/models 2>/dev/null || echo no models'
