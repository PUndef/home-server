#!/bin/bash
# Base phoneserver setup after v25.12 flash (before HA restore).
# Run from WSL/PC: PHONE_IP=<wifi-ip> bash scripts/phoneserver/migrate-v2512/post-flash-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/../phone-defaults.sh"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")
PMOS_PASS="${PMOS_PASS:-changemenow}"

echo "[post-flash] target pmos@${PHONE_IP}"

# SSH key
"${SCRIPT_DIR}/../setup-ssh-key.sh"

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" bash -s <<REMOTE
set -euo pipefail
PMOS_PASS='${PMOS_PASS}'

# passwordless sudo (v25.12 may ship doas or sudo)
if command -v apk >/dev/null; then
    apk add --no-cache sudo openssh-server chrony docker docker-cli-compose docker-openrc 2>/dev/null || true
fi
mkdir -p /etc/sudoers.d
echo 'pmos ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/pmos-nopasswd
chmod 0440 /etc/sudoers.d/pmos-nopasswd

# resize root (userdata partition)
ROOT_DEV=\$(findmnt -n -o SOURCE /)
sudo resize2fs "\$ROOT_DEV" 2>/dev/null || true

# DNS pin (sing-box bypass on lan router)
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf >/dev/null
if [ -f /etc/dhcpcd.conf ]; then
    grep -q 'nohook resolv.conf' /etc/dhcpcd.conf || echo 'nohook resolv.conf' | sudo tee -a /etc/dhcpcd.conf >/dev/null
fi

sudo rc-update add chronyd boot 2>/dev/null || systemctl enable chronyd 2>/dev/null || true
sudo rc-update add docker boot 2>/dev/null || systemctl enable docker 2>/dev/null || true
sudo rc-service chronyd start 2>/dev/null || sudo systemctl start chronyd 2>/dev/null || true

hostnamectl set-hostname phoneserver 2>/dev/null || echo phoneserver | sudo tee /etc/hostname >/dev/null

echo '[post-flash] identity:'
hostname; uname -r; df -h / | tail -1
REMOTE

echo "[post-flash] done — run smoke-test before HA restore"
