#!/bin/bash
# Turn asidko Phosh image into phoneserver headless (after flash, before HA).
# Usage: PHONE_IP=<wifi-ip> PMOS_PASS=1234 bash post-flash-headless.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/../phone-defaults.sh"
PMOS_PASS="${PMOS_PASS:-1234}"
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

echo "[headless] target user@${PHONE_IP} (asidko default user/1234)"

# Push our SSH key (setup-ssh-key expects pmos — use user for first login)
if [ -f "$HOME/.ssh/phoneserver_nopass.pub" ]; then
    sshpass -p "$PMOS_PASS" ssh-copy-id -i "$HOME/.ssh/phoneserver_nopass.pub" \
        -o StrictHostKeyChecking=no "user@${PHONE_IP}" 2>/dev/null || \
    cat "$HOME/.ssh/phoneserver_nopass.pub" | sshpass -p "$PMOS_PASS" ssh \
        -o StrictHostKeyChecking=no "user@${PHONE_IP}" \
        "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys"
fi

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}" "user@${PHONE_IP}" \
    "echo '$PMOS_PASS' | sudo -S sh -s" <<'REMOTE'
set -eu
# headless: stop graphical target, keep sshd/docker-ready base
rc-update del dbus boot 2>/dev/null || true
apk add --no-cache sudo openssh-server chrony docker docker-cli-compose docker-openrc 2>/dev/null || true

hostnamectl set-hostname phoneserver 2>/dev/null || echo phoneserver > /etc/hostname
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /etc/resolv.conf

ROOT_DEV=$(findmnt -n -o SOURCE /)
resize2fs "$ROOT_DEV" 2>/dev/null || true

mkdir -p /etc/sudoers.d
echo 'user ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/user-nopasswd
chmod 0440 /etc/sudoers.d/user-nopasswd

rc-update add chronyd boot 2>/dev/null || systemctl enable chronyd 2>/dev/null || true
rc-update add docker boot 2>/dev/null || systemctl enable docker 2>/dev/null || true

echo "kernel=$(uname -r) hostname=$(hostname) root=$(df -h / | tail -1)"
REMOTE

echo "[headless] next: install-asidko-charger-v062.sh → reboot → smoke-test"
