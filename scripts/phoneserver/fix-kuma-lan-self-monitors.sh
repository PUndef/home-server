#!/bin/sh
set -eu

echo "=== beszel-agent ==="
sudo rc-service beszel-agent status 2>&1 || true
sudo rc-service beszel-agent restart 2>&1 || true
sleep 2
sudo rc-service beszel-agent status 2>&1 || true
ss -lntp 2>/dev/null | grep 45876 || echo "45876 not listening"

echo "=== ssh :22 from shell ==="
nc -zv -w 2 192.168.1.116 22 2>&1 || true

echo "=== remove self LAN monitors (Kuma on phone cannot check its own IP) ==="
DB=/var/lib/uptime-kuma/data/kuma.db
sudo sqlite3 "$DB" <<'SQL'
DELETE FROM heartbeat WHERE monitor_id IN (13, 14);
DELETE FROM monitor WHERE id IN (13, 14);
SELECT id, name, hostname, port FROM monitor WHERE name LIKE 'phoneserver%';
SQL

sudo rc-service uptime-kuma restart
echo done
