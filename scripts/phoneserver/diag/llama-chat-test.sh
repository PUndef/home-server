#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
PROMPT=${PROMPT:-"In two short sentences, explain why postmarketOS is a good fit for repurposing an old Android phone as a home server."}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "LD_LIBRARY_PATH=\$HOME/llama.cpp/build/bin \
        \$HOME/llama.cpp/build/bin/llama-cli \
        -m \$HOME/models/Qwen2.5-3B-Instruct-Q4_K_M.gguf \
        -t 6 \
        -n 128 \
        --temp 0.4 \
        --no-conversation \
        -p \"$PROMPT\" 2>&1 | tail -40"
