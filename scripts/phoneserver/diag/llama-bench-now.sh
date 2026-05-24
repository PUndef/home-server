#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'cd $HOME
ls -lh models/
echo
echo "=== llama-bench (Qwen2.5 3B Q4_K_M) ==="
LD_LIBRARY_PATH=$HOME/llama.cpp/build/bin \
    $HOME/llama.cpp/build/bin/llama-bench \
    -m $HOME/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf \
    -t 6 -p 32 -n 64 -r 2 2>&1 | tail -30'
