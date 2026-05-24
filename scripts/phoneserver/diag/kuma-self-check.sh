#!/bin/sh
set -eu
echo "=== listen 3001 ==="
ss -lntp 2>/dev/null | grep 3001 || netstat -lntp 2>/dev/null | grep 3001 || true
echo "=== curl targets ==="
for u in http://127.0.0.1:3001/ http://192.168.1.116:3001/ http://0.0.0.0:3001/; do
  echo "-- $u --"
  timeout 8 curl -sI --connect-timeout 3 --max-time 6 "$u" 2>&1 | head -4 || echo TIMEOUT/FAIL
done
echo "=== nc port 3001 ==="
timeout 3 nc -zv 127.0.0.1 3001 2>&1 || true
timeout 3 nc -zv 192.168.1.116 3001 2>&1 || true
echo "=== latest self heartbeats ==="
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db \
  "SELECT datetime(time,'unixepoch','localtime'), status, msg FROM heartbeat WHERE monitor_id=15 ORDER BY id DESC LIMIT 5;" 2>/dev/null || true
