#!/bin/bash
# Restore Home Assistant ONLY after smoke-test passes.
# Run from PC/WSL with backup on jump host or local path.
#
# Usage:
#   BACKUP=/root/backups/phoneserver-pre-v2512/homeassistant-config-20260612-183841.tar.gz \
#   PHONE_IP=192.168.1.227 \
#   bash scripts/phoneserver/migrate-v2512/restore-ha.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/../phone-defaults.sh"

BACKUP="${BACKUP:-}"
JUMP="${JUMP:-root@192.168.50.9}"
JUMP_KEY="${JUMP_KEY:-$HOME/.ssh/proxmox_pundef_nopass}"
REMOTE_BACKUP_DEFAULT="/root/backups/phoneserver-pre-v2512/homeassistant-config-20260612-183841.tar.gz"

if [ -z "$BACKUP" ]; then
    BACKUP="$REMOTE_BACKUP_DEFAULT"
fi

SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")

echo "[restore-ha] smoke-test gate..."
ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" "sudo sh -s" < "${SCRIPT_DIR}/../smoke-test-post-flash.sh" || {
    echo "[restore-ha] ABORT: smoke-test failed — fix base system first"
    exit 1
}

echo "[restore-ha] uploading backup..."
if [[ "$BACKUP" == /* ]] && ssh -i "$JUMP_KEY" "$JUMP" "test -f '$BACKUP'" 2>/dev/null; then
    ssh -i "$JUMP_KEY" "$JUMP" "cat '$BACKUP'" | ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" \
        "cat > /tmp/ha-restore.tar.gz"
else
    scp "${SSH_OPTS[@]}" "$BACKUP" "pmos@${PHONE_IP}:/tmp/ha-restore.tar.gz"
fi

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" bash -s <<'REMOTE'
set -euo pipefail
sudo mkdir -p /opt/homeassistant
sudo tar xzf /tmp/ha-restore.tar.gz -C /opt/homeassistant
sudo chown -R pmos:pmos /opt/homeassistant
rm -f /tmp/ha-restore.tar.gz
REMOTE

"${SCRIPT_DIR}/../install-homeassistant.sh"
echo "[restore-ha] HA restored — verify http://${PHONE_IP}:8123"
