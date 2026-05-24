#!/bin/sh
echo "=== resolv.conf ==="
cat /etc/resolv.conf
echo "=== hosts ==="
cat /etc/hosts
echo "=== nsswitch ==="
cat /etc/nsswitch.conf 2>/dev/null || true
echo "=== dig @1.1.1.1 ==="
dig +short cloud-pundef.mooo.com @1.1.1.1 2>/dev/null || nslookup cloud-pundef.mooo.com 1.1.1.1 2>/dev/null
echo "=== dig @8.8.8.8 ==="
dig +short apps-pundef.mooo.com @8.8.8.8 2>/dev/null || true
echo "=== getent ==="
getent hosts cloud-pundef.mooo.com
echo "=== curl direct to 192.168.50.34 ==="
curl -sI --connect-timeout 10 http://192.168.50.34/ | head -5
