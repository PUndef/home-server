#!/bin/sh
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db \
  "SELECT m.id, m.name, m.hostname, m.port, h.status, h.msg FROM monitor m LEFT JOIN heartbeat h ON h.id=(SELECT MAX(id) FROM heartbeat WHERE monitor_id=m.id) WHERE m.id IN (13,14);"
