#!/bin/sh
set -eu

echo "=== resolve ==="
for h in cloud-pundef.mooo.com apps-pundef.mooo.com; do
  echo -n "$h -> "
  getent hosts "$h" || nslookup "$h" 2>/dev/null | tail -3 || true
done

echo "=== cloud verbose TLS ==="
curl -vI --connect-timeout 15 https://cloud-pundef.mooo.com/ 2>&1 | tail -25

echo "=== cloud -k verbose ==="
curl -vI --connect-timeout 15 -k https://cloud-pundef.mooo.com/ 2>&1 | tail -15

echo "=== kuma db ==="
sudo ls -la /var/lib/uptime-kuma/data/ 2>/dev/null || ls -la /var/lib/uptime-kuma/data/ 2>/dev/null || true
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db ".schema monitor" 2>/dev/null | head -5 || true
sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db "SELECT id, name, url, ignore_tls FROM monitor;" 2>/dev/null || true

echo "=== chrony ==="
rc-service chronyd status 2>&1 | head -3 || true
sudo rc-service chronyd status 2>&1 | head -3 || true
