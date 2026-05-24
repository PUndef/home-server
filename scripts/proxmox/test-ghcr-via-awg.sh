#!/bin/bash
echo "nameserver 192.168.50.1" > /etc/resolv.conf
echo "=== resolv.conf ==="
cat /etc/resolv.conf
echo
echo "=== dns test ==="
getent hosts ghcr.io
echo
echo "=== which IP we appear as (api.ipify.org) ==="
curl -sS -m 10 https://api.ipify.org/
echo
echo "=== ghcr direct probe ==="
curl -sI -m 10 https://ghcr.io 2>&1 | head -5
echo
echo "=== github direct probe ==="
curl -sI -m 10 https://github.com 2>&1 | head -5
