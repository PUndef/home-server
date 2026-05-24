#!/bin/bash
# Switch llama-server to a lighter ctx for everyday chat (faster than Morphic 16384).
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
NEW_CTX=${NEW_CTX:-4096}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "sudo sed -i 's/--ctx-size [0-9]*/--ctx-size ${NEW_CTX}/' /etc/init.d/llama-server
grep -o 'ctx-size [0-9]*' /etc/init.d/llama-server
sudo rc-service llama-server restart
sleep 10
curl -sS -m 15 http://127.0.0.1:8080/health || echo health_timeout
sudo rc-service llama-server status"
