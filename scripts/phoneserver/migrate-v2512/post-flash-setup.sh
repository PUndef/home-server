#!/bin/bash
# Base phoneserver setup after v25.12 flash (before HA restore).
# Run from WSL/PC: PHONE_IP=<wifi-ip> bash scripts/phoneserver/migrate-v2512/post-flash-setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/../phone-defaults.sh"

SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i "$SSH_KEY")

echo "[post-flash] target ${SSH_REMOTE}"

"${SCRIPT_DIR}/../setup-ssh-key.sh"

ssh "${SSH_OPTS[@]}" "${SSH_REMOTE}" bash -s <<REMOTE
set -euo pipefail

if command -v apk >/dev/null; then
    apk add --no-cache sudo openssh-server chrony docker docker-cli-compose 2>/dev/null || true
fi
mkdir -p /etc/sudoers.d
echo '${SSH_USER} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/${SSH_USER}-nopasswd
chmod 0440 /etc/sudoers.d/${SSH_USER}-nopasswd

ROOT_DEV=\$(findmnt -n -o SOURCE /)
sudo resize2fs "\$ROOT_DEV" 2>/dev/null || true

printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' | sudo tee /etc/resolv.conf >/dev/null
if [ -f /etc/dhcpcd.conf ]; then
    grep -q 'nohook resolv.conf' /etc/dhcpcd.conf || echo 'nohook resolv.conf' | sudo tee -a /etc/dhcpcd.conf >/dev/null
fi

sudo rc-update add chronyd boot 2>/dev/null || sudo systemctl enable chronyd 2>/dev/null || true
sudo rc-update add docker boot 2>/dev/null || sudo systemctl enable docker 2>/dev/null || true
sudo rc-service chronyd start 2>/dev/null || sudo systemctl start chronyd 2>/dev/null || true

hostnamectl set-hostname phoneserver 2>/dev/null || echo phoneserver | sudo tee /etc/hostname >/dev/null

echo '[post-flash] identity:'
hostname; uname -r; df -h / | tail -1
REMOTE

echo "[post-flash] done — run smoke-test before HA restore"
