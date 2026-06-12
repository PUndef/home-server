#!/bin/sh
set -eu
PHONE_IP="${PHONE_IP:-192.168.1.227}"
KEY="${PHONE_KEY:-$HOME/.ssh/phoneserver_nopass}"
OUT="${1:-/tmp/kuma-backup.db}"

# Online backup — не останавливаем Kuma (rc-service stop на pmOS часто зависает).
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=20 -i "$KEY" "pmos@${PHONE_IP}" \
  "sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db '.backup /tmp/kuma-backup.db' && ls -lh /tmp/kuma-backup.db"

scp -o StrictHostKeyChecking=no -i "$KEY" "pmos@${PHONE_IP}:/tmp/kuma-backup.db" "$OUT"
ls -lh "$OUT"
echo "saved: $OUT"
