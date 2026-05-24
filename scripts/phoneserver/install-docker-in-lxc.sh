#!/usr/bin/env bash
# Install Docker CE in LXC 103 (Debian 13) from docker.com.
set -e

cat <<'INNER' > /tmp/docker-bootstrap.sh
#!/bin/bash
set -e

apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg lsb-release git

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian $CODENAME stable" \
    > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

docker --version
docker compose version
INNER

py -3 scripts/proxmox/upload.py /tmp/docker-bootstrap.sh /tmp/docker-bootstrap.sh
py -3 scripts/proxmox/proxmox_exec.py "pct push 103 /tmp/docker-bootstrap.sh /root/docker-bootstrap.sh"
py -3 scripts/proxmox/proxmox_exec.py "pct exec 103 -- bash -lc 'chmod +x /root/docker-bootstrap.sh && /root/docker-bootstrap.sh'"
