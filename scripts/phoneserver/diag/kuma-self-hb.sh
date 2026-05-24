#!/bin/sh
sleep 70
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db \
  "SELECT datetime(time,'unixepoch','localtime'), status, msg FROM heartbeat WHERE monitor_id=15 ORDER BY id DESC LIMIT 3;"
