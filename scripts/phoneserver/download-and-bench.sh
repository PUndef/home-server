#!/bin/bash
# Download a small GGUF model and run llama-bench to measure tokens/s.
# Default: Qwen2.5 3B Instruct Q4_K_M from bartowski's HF mirror (~1.93 GB).
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
MODEL_URL=${MODEL_URL:-https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf}
MODEL_FILE=${MODEL_FILE:-Qwen2.5-3B-Instruct-Q4_K_M.gguf}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "set -e
    mkdir -p ~/models
    if [ ! -f ~/models/${MODEL_FILE} ]; then
        echo === download ===
        curl -L -# -o ~/models/${MODEL_FILE} '${MODEL_URL}'
    else
        echo === model already downloaded ===
    fi
    ls -lh ~/models/${MODEL_FILE}

    echo
    echo === llama-bench (token gen with default prompt) ===
    export LD_LIBRARY_PATH=\$HOME/llama.cpp/build/bin
    ~/llama.cpp/build/bin/llama-bench -m ~/models/${MODEL_FILE} -t 6 -p 32 -n 64 -r 2 2>&1 | tail -30"
