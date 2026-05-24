#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== binaries with server in name ==="
ls -la ~/llama.cpp/build/bin/ | grep -iE "server|cli|bench" 
echo
echo "=== llama-cli --version ==="
export LD_LIBRARY_PATH=$HOME/llama.cpp/build/bin
~/llama.cpp/build/bin/llama-cli --version 2>&1 | head
echo
echo "=== llama-server --help ==="
~/llama.cpp/build/bin/llama-server --help 2>&1 | head -3'
