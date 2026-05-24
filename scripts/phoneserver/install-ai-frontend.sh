#!/usr/bin/env bash
# Set up the LXC 103 'ai-frontend' as a Docker host for Morphic + SearXNG.
# This is a one-off bootstrap. Re-running is idempotent.

set -e

# Step 1: install curl + git + Docker
py -3 scripts/proxmox/proxmox_exec.py "pct exec 103 -- bash -lc '
apt update >/dev/null 2>&1
apt install -y curl git ca-certificates >/dev/null 2>&1
echo === probe phoneserver from inside LXC ===
curl -sS -m 5 http://192.168.1.116:8080/health || echo FAILED
'"

echo
echo "=== install docker ==="
py -3 scripts/proxmox/proxmox_exec.py "pct exec 103 -- bash -lc '
apt install -y docker.io docker-compose-v2 2>&1 | tail -3
systemctl enable --now docker
docker --version
docker compose version
'"
