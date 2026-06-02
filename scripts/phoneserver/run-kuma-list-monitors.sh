#!/usr/bin/env bash
set -euo pipefail
KEY="${PHONE_SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
REMOTE="${PHONE_SSH_USER:-pmos}@${PHONE_IP:-192.168.1.116}"
ssh -i "$KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=15 "$REMOTE" \
  'sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db "SELECT id,name,type,url,hostname FROM monitor ORDER BY id;"'
