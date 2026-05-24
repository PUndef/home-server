#!/bin/bash
# Refresh term-status every N seconds (local or remote).
#   ./watch-status.sh
#   PHONE_IP=192.168.1.116 ./watch-status.sh remote

INTERVAL="${INTERVAL:-3}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while true; do
    clear 2>/dev/null || printf '\033[2J\033[H'
    if [ "${1:-}" = "remote" ]; then
        PHONE_IP="${PHONE_IP:-192.168.1.116}"
        SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
        ssh -o StrictHostKeyChecking=no -t -i "${SSH_KEY}" "pmos@${PHONE_IP}" \
            "sh -s" < "${SCRIPT_DIR}/term-status.sh" || true
    else
        sh "${SCRIPT_DIR}/term-status.sh" || true
    fi
    sleep "${INTERVAL}"
done
