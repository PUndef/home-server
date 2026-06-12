#!/usr/bin/env bash
# Manual Kuma migration steps (WSL). PHONE_IP=192.168.1.227
set -euo pipefail

REPO="/mnt/d/repositories/home-server"
PHONE_IP="${PHONE_IP:-192.168.1.227}"
PHONE_KEY="${PHONE_KEY:-$HOME/.ssh/phoneserver_nopass}"
LXC_VMID="${LXC_VMID:-102}"
BACKUP_LOCAL="/tmp/kuma-backup.db"
BACKUP_REMOTE="/tmp/kuma-backup.db"

SSH_PHONE=(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i "${PHONE_KEY}" "pmos@${PHONE_IP}")
SCP_PHONE=(scp -o StrictHostKeyChecking=no -i "${PHONE_KEY}")

proxmox() { python3 "${REPO}/scripts/proxmox/proxmox_exec.py" "$@"; }
upload() { python3 "${REPO}/scripts/proxmox/upload.py" "$@"; }

echo "=== 1. online backup kuma.db on phoneserver ==="
"${SSH_PHONE[@]}" sh -s <<'REMOTE'
set -eu
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db '.backup /tmp/kuma-backup.db'
ls -lh /tmp/kuma-backup.db
REMOTE

echo "=== 2. scp backup to WSL ==="
"${SCP_PHONE[@]}" "pmos@${PHONE_IP}:${BACKUP_REMOTE}" "${BACKUP_LOCAL}"
ls -lh "${BACKUP_LOCAL}"

echo "=== 3. push scripts + backup to Proxmox / LXC ==="
upload "${REPO}/scripts/proxmox/uptime-kuma-install.sh" /tmp/uptime-kuma-install.sh --chmod 755
upload "${REPO}/scripts/proxmox/fix-kuma-monitors-lxc.sh" /tmp/fix-kuma-monitors-lxc.sh --chmod 755
upload "${BACKUP_LOCAL}" /tmp/kuma-backup.db

proxmox "pct push ${LXC_VMID} /tmp/uptime-kuma-install.sh /tmp/uptime-kuma-install.sh --perms 0755"
proxmox "pct push ${LXC_VMID} /tmp/fix-kuma-monitors-lxc.sh /tmp/fix-kuma-monitors-lxc.sh --perms 0755"
proxmox "pct push ${LXC_VMID} /tmp/kuma-backup.db /tmp/kuma-backup.db"

echo "=== 4. install Kuma on LXC (npm may take 5-15 min) ==="
proxmox "pct exec ${LXC_VMID} -- bash -lc 'KUMA_VERSION=2.3.2 /tmp/uptime-kuma-install.sh'"

echo "=== 5. restore DB + fix monitors ==="
proxmox "pct exec ${LXC_VMID} -- bash -lc '
  systemctl stop uptime-kuma
  install -d -o uptime-kuma -g uptime-kuma -m 750 /var/lib/uptime-kuma/data
  cp /tmp/kuma-backup.db /var/lib/uptime-kuma/data/kuma.db
  chown uptime-kuma:uptime-kuma /var/lib/uptime-kuma/data/kuma.db
'"
proxmox "pct exec ${LXC_VMID} -- bash /tmp/fix-kuma-monitors-lxc.sh"

echo "=== 6. stop Kuma on phoneserver ==="
"${SSH_PHONE[@]}" sh -s <<'REMOTE'
set -eu
sudo rc-update del uptime-kuma default 2>/dev/null || true
sudo rc-service uptime-kuma stop 2>/dev/null || true
sudo rc-service uptime-kuma status 2>&1 | head -2 || true
REMOTE

echo "=== 7. verify ==="
proxmox "pct exec ${LXC_VMID} -- curl -sS -m 5 -o /dev/null -w 'kuma:%{http_code}\n' http://127.0.0.1:3001/"
curl -sS -m 8 -o /dev/null -w "kuma-lan:%{http_code}\n" "http://192.168.50.35:3001/" || true

echo "done — http://192.168.50.35:3001/"
