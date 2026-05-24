#!/bin/sh
# Kuma cannot monitor its own :3001 (HTTP or TCP) from the same process — remove self-check.
set -eu
DB=/var/lib/uptime-kuma/data/kuma.db

echo "=== delete self monitor ==="
sudo sqlite3 "$DB" <<'SQL'
DELETE FROM heartbeat WHERE monitor_id IN (SELECT id FROM monitor WHERE name = 'Uptime Kuma (self)');
DELETE FROM monitor WHERE name = 'Uptime Kuma (self)';
SELECT id, name FROM monitor ORDER BY id;
SQL

sudo rc-service uptime-kuma restart
echo "removed — use Beszel or http://192.168.1.116:3001/ from PC for health"
