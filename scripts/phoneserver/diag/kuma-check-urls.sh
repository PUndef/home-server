#!/bin/sh
# Run on phoneserver: check HTTPS targets for Uptime Kuma monitors.
set -eu

echo "=== date ==="
date
chronyc tracking 2>/dev/null | head -3 || true

echo "=== kuma local ==="
curl -sI --connect-timeout 5 http://127.0.0.1:3001/ | head -3 || echo FAIL

for u in \
  'https://cloud-pundef.mooo.com/' \
  'https://apps-pundef.mooo.com/beszel/api/health' \
  'https://apps-pundef.mooo.com/requiem/'
do
  echo "=== URL: $u ==="
  echo "-- strict TLS --"
  curl -sI --connect-timeout 15 "$u" 2>&1 | head -8 || true
  echo "-- insecure (-k) --"
  curl -sI --connect-timeout 15 -k "$u" 2>&1 | head -5 || true
  echo
done

echo "=== sqlite monitors (ignoreTls) ==="
if [ -f /var/lib/uptime-kuma/data/kuma.db ]; then
  sqlite3 /var/lib/uptime-kuma/data/kuma.db \
    "SELECT id, name, url, ignore_tls FROM monitor WHERE type='http' ORDER BY id;" 2>/dev/null || true
fi
