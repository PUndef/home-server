#!/bin/sh
# Fix phoneserver DNS for homelab domains + patch Kuma HTTP monitors.
set -eu

HOSTS_BLOCK='# homelab LAN — public DNS for *.mooo.com points at stale VPS (5.189.245.251)
192.168.50.34 cloud-pundef.mooo.com apps-pundef.mooo.com'

echo "=== /etc/hosts homelab entries ==="
if ! grep -q 'cloud-pundef.mooo.com' /etc/hosts; then
    echo "$HOSTS_BLOCK" | sudo tee -a /etc/hosts >/dev/null
    echo "added hosts entries"
else
    echo "already present"
fi
grep mooo /etc/hosts || true

echo
echo "=== verify resolve ==="
getent hosts cloud-pundef.mooo.com
getent hosts apps-pundef.mooo.com

echo
echo "=== curl HTTPS after hosts fix ==="
for u in \
  'https://cloud-pundef.mooo.com/' \
  'https://apps-pundef.mooo.com/beszel/api/health' \
  'https://apps-pundef.mooo.com/requiem/'
do
    echo "-- $u --"
    curl -sI --connect-timeout 15 "$u" 2>&1 | head -4 || true
done

echo
echo "=== patch kuma.db: ignore_tls + fix URLs if needed ==="
DB=/var/lib/uptime-kuma/data/kuma.db
sudo sqlite3 "$DB" "UPDATE monitor SET ignore_tls=1 WHERE type='http' AND url LIKE 'https://%';"
sudo sqlite3 "$DB" "SELECT id, name, url, ignore_tls FROM monitor WHERE type='http';"

echo
echo "=== restart uptime-kuma ==="
sudo rc-service uptime-kuma restart
sleep 2
sudo rc-service uptime-kuma status | head -2
