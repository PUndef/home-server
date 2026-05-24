#!/bin/bash
# Increase llama-server context size to 16384 to accommodate Morphic's
# tool-call prompts (4-5k tokens easily) and restart the service.
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
NEW_CTX=${NEW_CTX:-16384}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "sudo sed -i 's/--ctx-size [0-9]*/--ctx-size ${NEW_CTX}/' /etc/init.d/llama-server
grep -o 'ctx-size [0-9]*' /etc/init.d/llama-server
sudo rc-service llama-server restart
sleep 12
sudo rc-service llama-server status
echo
echo === free ===
free -h | head -3
echo
echo === probe ===
curl -sS -m 5 http://192.168.1.116:8080/v1/models | head -c 200"
