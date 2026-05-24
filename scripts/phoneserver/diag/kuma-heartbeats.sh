#!/bin/sh
sleep 65
sudo apk add --no-cache sqlite >/dev/null 2>&1 || true
echo "=== latest heartbeats ==="
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db \
  "SELECT m.name, h.status, h.msg FROM heartbeat h JOIN monitor m ON m.id=h.monitor_id ORDER BY h.id DESC LIMIT 5;"
