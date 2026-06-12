#!/usr/bin/env bash
# Probe Kuma monitor targets from static-sites LXC (where Kuma runs).
set -eu

echo "=== /etc/hosts ==="
grep mooo /etc/hosts || echo "(no mooo hosts)"

echo
echo "=== ping ==="
for h in 192.168.50.9 192.168.50.34 192.168.50.35 192.168.50.36 192.168.1.1 192.168.1.171 192.168.1.227 89.44.76.52; do
  if ping -c1 -W2 "$h" >/dev/null 2>&1; then
    echo "OK  ping $h"
  else
    echo "FAIL ping $h"
  fi
done

echo
echo "=== port 8006 proxmox ==="
if timeout 3 bash -c 'echo >/dev/tcp/192.168.50.9/8006' 2>/dev/null; then
  echo "OK  tcp 192.168.50.9:8006"
else
  echo "FAIL tcp 192.168.50.9:8006"
fi

echo
echo "=== port 22 NL vps ==="
if timeout 5 bash -c 'echo >/dev/tcp/45.154.35.222/22' 2>/dev/null; then
  echo "OK  tcp 45.154.35.222:22"
else
  echo "FAIL tcp 45.154.35.222:22"
fi

echo
echo "=== http/https ==="
probe() {
  u="$1"
  code=$(curl -k -sS -m10 -o /dev/null -w '%{http_code}' "$u" 2>/dev/null || echo curl-fail)
  echo "$code  $u"
}
probe "https://cloud-pundef.mooo.com/"
probe "https://apps-pundef.mooo.com/beszel/api/health"
probe "https://owncord-pundef.mooo.com/api/health"
probe "https://apps-pundef.mooo.com/requiem/"
probe "http://192.168.50.34/"
probe "http://192.168.50.36:3001/api/health"
probe "http://192.168.1.227:8123/"

echo
echo "=== kuma.db ignore_tls (https monitors) ==="
DB=/var/lib/uptime-kuma/data/kuma.db
if [ -f "$DB" ]; then
  sqlite3 "$DB" "SELECT id,name,ignore_tls,url FROM monitor WHERE type='http' AND url LIKE 'https://%';"
else
  echo "no db"
fi
