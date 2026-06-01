#!/usr/bin/env bash
# coturn for OwnCord on LXC 103. Run inside LXC as root.
set -euo pipefail

TURN_DIR="${TURN_DIR:-/opt/owncord/deploy/turn}"
LAN_IP="${TURN_LAN_IP:-192.168.50.36}"
WAN_IP="${TURN_WAN_IP:-5.189.245.251}"
REALM="${TURN_REALM:-owncord-pundef.mooo.com}"
USER="${TURN_USERNAME:-owncord}"
PASS="${TURN_PASSWORD:-$(openssl rand -hex 16)}"
ENV_FILE="/opt/owncord/server/.env"

if [[ ! -d "$TURN_DIR" ]]; then
  echo "[owncord-turn] missing $TURN_DIR — clone/update OwnCord first" >&2
  exit 1
fi

cd "$TURN_DIR"

cat >.env <<EOF
REALM=${REALM}
TURN_USERNAME=${USER}
TURN_PASSWORD=${PASS}
EXTERNAL_IP=${WAN_IP}/${LAN_IP}
EOF

# Homelab: allow relay between LAN clients (default upstream denies RFC1918).
cat >turnserver.conf <<EOF
listening-port=3478
external-ip=${WAN_IP}/${LAN_IP}
min-port=49152
max-port=65535
fingerprint
lt-cred-mech
realm=${REALM}
user=${USER}:${PASS}
no-multicast-peers
no-cli
no-loopback-peers
denied-peer-ip=0.0.0.0-0.255.255.255
denied-peer-ip=127.0.0.0-127.255.255.255
denied-peer-ip=169.254.0.0-169.254.255.255
denied-peer-ip=224.0.0.0-255.255.255.255
log-file=stdout
simple-log
verbose
EOF

docker compose pull
docker compose up -d
docker compose ps

# Wire into OwnCord server .env
touch "$ENV_FILE"
grep -q '^TURN_URL=' "$ENV_FILE" && sed -i "s|^TURN_URL=.*|TURN_URL=turn:${LAN_IP}:3478|" "$ENV_FILE" || echo "TURN_URL=turn:${LAN_IP}:3478" >>"$ENV_FILE"
grep -q '^TURN_USERNAME=' "$ENV_FILE" && sed -i "s|^TURN_USERNAME=.*|TURN_USERNAME=${USER}|" "$ENV_FILE" || echo "TURN_USERNAME=${USER}" >>"$ENV_FILE"
grep -q '^TURN_PASSWORD=' "$ENV_FILE" && sed -i "s|^TURN_PASSWORD=.*|TURN_PASSWORD=${PASS}|" "$ENV_FILE" || echo "TURN_PASSWORD=${PASS}" >>"$ENV_FILE"

systemctl restart owncord
sleep 2
systemctl is-active owncord
curl -fsS http://127.0.0.1:3001/api/ice

echo
echo "[owncord-turn] TURN_URL=turn:${LAN_IP}:3478 user=${USER} pass=${PASS}"
