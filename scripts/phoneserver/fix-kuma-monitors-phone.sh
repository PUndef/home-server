#!/bin/sh
# Fix phoneserver DNS for homelab domains + patch Kuma HTTP monitors.
set -eu

HOSTS_BLOCK='# homelab LAN — public DNS for *.mooo.com points at stale VPS (5.189.245.251)
192.168.50.34 cloud-pundef.mooo.com apps-pundef.mooo.com owncord-pundef.mooo.com'

echo "=== /etc/hosts homelab entries ==="
if ! grep -q 'cloud-pundef.mooo.com' /etc/hosts; then
    echo "$HOSTS_BLOCK" | sudo tee -a /etc/hosts >/dev/null
    echo "added hosts block"
else
    echo "cloud/apps hosts already present"
fi
if ! grep -q 'owncord-pundef.mooo.com' /etc/hosts; then
    echo '192.168.50.34 owncord-pundef.mooo.com' | sudo tee -a /etc/hosts >/dev/null
    echo "added owncord-pundef.mooo.com"
fi
grep mooo /etc/hosts || true

echo
echo "=== verify resolve ==="
getent hosts cloud-pundef.mooo.com
getent hosts apps-pundef.mooo.com
getent hosts owncord-pundef.mooo.com

echo
echo "=== curl HTTPS after hosts fix ==="
for u in \
  'https://cloud-pundef.mooo.com/' \
  'https://apps-pundef.mooo.com/beszel/api/health' \
  'https://apps-pundef.mooo.com/requiem/' \
  'https://owncord-pundef.mooo.com/api/health'
do
    echo "-- $u --"
    curl -sI --connect-timeout 15 "$u" 2>&1 | head -4 || true
done

echo
echo "=== patch kuma.db: ignore_tls + fix URLs if needed ==="
DB=/var/lib/uptime-kuma/data/kuma.db
sudo sqlite3 "$DB" "UPDATE monitor SET ignore_tls=1 WHERE type='http' AND url LIKE 'https://%';"

echo
echo "=== add OwnCord monitors (idempotent) ==="
# Group ids on this phone: Public HTTPS=2, srv=5
sudo sqlite3 "$DB" <<'SQL'
INSERT INTO monitor (name, active, user_id, interval, url, type, weight, maxretries, ignore_tls, accepted_statuscodes_json, method, parent, conditions)
SELECT 'OwnCord', 1, 1, 60, 'https://owncord-pundef.mooo.com/api/health', 'http', 2000, 3, 1, '["200-299"]', 'GET', 2, '[]'
WHERE NOT EXISTS (SELECT 1 FROM monitor WHERE name='OwnCord');

INSERT INTO monitor (name, active, user_id, interval, hostname, type, weight, parent, conditions, ping_count, ping_numeric, ping_per_request_timeout)
SELECT 'owncord LXC', 1, 1, 60, '192.168.50.36', 'ping', 2000, 5, '[]', 1, 1, 2
WHERE NOT EXISTS (SELECT 1 FROM monitor WHERE name='owncord LXC');

INSERT INTO monitor (name, active, user_id, interval, url, type, weight, maxretries, parent, conditions)
SELECT 'OwnCord backend (LAN)', 1, 1, 120, 'http://192.168.50.36:3001/api/health', 'http', 2000, 0, 5, '[]'
WHERE NOT EXISTS (SELECT 1 FROM monitor WHERE name='OwnCord backend (LAN)');
SQL
sudo sqlite3 "$DB" "SELECT id, name, type, url, hostname FROM monitor WHERE name LIKE '%wnCord%' OR name LIKE 'owncord%';"

sudo sqlite3 "$DB" "SELECT id, name, url, ignore_tls FROM monitor WHERE type='http';"

echo
echo "=== restart uptime-kuma ==="
sudo rc-service uptime-kuma restart
sleep 2
sudo rc-service uptime-kuma status | head -2
