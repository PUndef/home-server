#!/usr/bin/env bash
# Fix Uptime Kuma on static-sites: split-horizon hosts + TLS flags in kuma.db.
set -euo pipefail

HOSTS_BLOCK='# homelab LAN — public DNS for *.mooo.com points at stale VPS (5.189.245.251)
192.168.50.34 cloud-pundef.mooo.com apps-pundef.mooo.com owncord-pundef.mooo.com'

echo "=== /etc/hosts homelab entries ==="
if ! grep -q 'cloud-pundef.mooo.com' /etc/hosts; then
  echo "$HOSTS_BLOCK" >>/etc/hosts
  echo "added hosts block"
else
  echo "cloud/apps hosts already present"
fi

echo
echo "=== verify resolve ==="
getent hosts cloud-pundef.mooo.com
getent hosts apps-pundef.mooo.com
getent hosts owncord-pundef.mooo.com

echo
echo "=== patch kuma.db: ignore_tls for HTTPS monitors ==="
DB=/var/lib/uptime-kuma/data/kuma.db
if [ ! -f "${DB}" ]; then
  echo "WARN: ${DB} not found — skip sqlite patch" >&2
else
  sqlite3 "${DB}" "UPDATE monitor SET ignore_tls=1 WHERE type='http' AND url LIKE 'https://%';"
  sqlite3 "${DB}" "SELECT id, name, url, ignore_tls FROM monitor WHERE type='http' ORDER BY id;"
fi

echo
echo "=== restart uptime-kuma ==="
systemctl restart uptime-kuma
sleep 2
systemctl is-active uptime-kuma
