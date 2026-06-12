#!/usr/bin/env bash
# Set ignore_tls=1 on all HTTPS monitors in Kuma DB (self-signed / split-horizon).
set -eu
DB=/var/lib/uptime-kuma/data/kuma.db
if [ ! -f "$DB" ]; then
  echo "no db: $DB" >&2
  exit 1
fi
sqlite3 "$DB" "UPDATE monitor SET ignore_tls=1 WHERE type='http' AND url LIKE 'https://%';"
sqlite3 "$DB" "SELECT id,name,ignore_tls,url FROM monitor WHERE type='http' ORDER BY id;"
systemctl restart uptime-kuma
sleep 2
systemctl is-active uptime-kuma
