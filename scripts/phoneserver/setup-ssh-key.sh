#!/bin/bash
# Generate a dedicated, passwordless ed25519 key for phoneserver and install it
# into pmos@phoneserver:~/.ssh/authorized_keys. Mirrors the style of
# ~/.ssh/proxmox_pundef_nopass used for the Proxmox host.

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
    "pmos@${PHONE_IP}"

echo
echo "=== passwordless test ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$KEY" "pmos@${PHONE_IP}" \
    'whoami; hostname'
