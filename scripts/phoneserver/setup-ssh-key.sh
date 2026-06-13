#!/bin/bash
# Generate a dedicated, passwordless ed25519 key for phoneserver and install it
# into user@phoneserver:~/.ssh/authorized_keys.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/phone-defaults.sh"
KEY="${SSH_KEY}"
INITIAL_PASS=${INITIAL_PASS:-changemenow}

if [ ! -f "$KEY" ]; then
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    ssh-keygen -t ed25519 -N "" -C "phoneserver@wsl" -f "$KEY"
fi

echo "=== local key ==="
ls -la "$KEY" "$KEY.pub"
echo "=== public key ==="
cat "$KEY.pub"

echo
echo "=== install on phone ==="
sshpass -p "$INITIAL_PASS" ssh-copy-id \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -i "$KEY.pub" \
    "${SSH_REMOTE}"

echo
echo "=== passwordless test ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$KEY" "${SSH_REMOTE}" \
    'whoami; hostname'
