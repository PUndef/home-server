#!/bin/bash
# Stop and disable llama-server on phoneserver.
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'sudo rc-service llama-server stop 2>/dev/null || true
sudo rc-update del llama-server default 2>/dev/null || true
sudo rc-service llama-server status 2>&1 || echo stopped
ss -tln | grep 8080 || echo port 8080 free'
