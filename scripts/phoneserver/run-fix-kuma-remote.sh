#!/usr/bin/env bash
# Run fix-kuma-monitors-phone.sh on phoneserver from WSL/Linux.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEY="${PHONE_SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
REMOTE="${PHONE_SSH_USER:-pmos}@${PHONE_IP:-192.168.1.116}"
SCP=(scp -i "$KEY" -o StrictHostKeyChecking=no)
SSH=(ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15)
"${SCP[@]}" "${SCRIPT_DIR}/fix-kuma-monitors-phone.sh" "${REMOTE}:/tmp/fix-kuma-monitors-phone.sh"
"${SSH[@]}" "$REMOTE" 'chmod 755 /tmp/fix-kuma-monitors-phone.sh && sh /tmp/fix-kuma-monitors-phone.sh'
