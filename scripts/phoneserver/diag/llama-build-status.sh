#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== running build procs ==="
ps -ef | grep -Ev "grep|sshd|sudo|tmux" | grep -E "cc1|gmake|cmake|gcc|ld" | head
echo
echo "=== llama.cpp/build/bin contents ==="
ls -la ~/llama.cpp/build/bin/ 2>/dev/null | head -40
echo
echo "=== free / load ==="
free -h
uptime
echo
echo "=== linux-headers installed? ==="
apk info -e linux-headers 2>&1'
