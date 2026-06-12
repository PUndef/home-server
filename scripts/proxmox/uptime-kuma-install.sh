#!/usr/bin/env bash
# uptime-kuma-install.sh — Uptime Kuma on Debian (systemd).
# Target: LXC static-sites (102) or any Debian host with systemd.
#
# Idempotent. Env: KUMA_VERSION, KUMA_PORT, KUMA_HOST

set -euo pipefail

KUMA_VERSION="${KUMA_VERSION:-2.3.2}"
KUMA_PORT="${KUMA_PORT:-3001}"
KUMA_HOST="${KUMA_HOST:-0.0.0.0}"

INSTALL_DIR="/opt/uptime-kuma"
DATA_DIR="/var/lib/uptime-kuma"
ENV_FILE="/etc/default/uptime-kuma"
SERVICE_PATH="/etc/systemd/system/uptime-kuma.service"
MARKER="${INSTALL_DIR}/.install-version"
LOG="/var/log/uptime-kuma-install.log"

log() {
  printf '[uptime-kuma-install] %s\n' "$*"
  printf '[uptime-kuma-install] %s\n' "$*" >>"${LOG}"
}

need_node_major=20

log "starting (version ${KUMA_VERSION}, listen ${KUMA_HOST}:${KUMA_PORT})"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates git sqlite3

if ! command -v node >/dev/null 2>&1; then
  apt-get install -y -qq nodejs npm
fi

if ! command -v node >/dev/null 2>&1; then
  log "ERROR: node not found after apt install" >&2
  exit 1
fi

node_major="$(node -p "Number(process.versions.node.split('.')[0])")"
if [ "${node_major}" -lt "${need_node_major}" ]; then
  log "ERROR: node $(node -v) too old; need >= ${need_node_major}" >&2
  exit 1
fi
log "node $(node -v), npm $(npm -v)"

if ! id uptime-kuma >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin \
    --home-dir "${DATA_DIR}" uptime-kuma
  log "created user uptime-kuma"
fi

install -d -m 750 -o uptime-kuma -g uptime-kuma "${DATA_DIR}/data" "${DATA_DIR}/.npm"

if [ ! -d "${INSTALL_DIR}/.git" ]; then
  log "cloning louislam/uptime-kuma ${KUMA_VERSION}"
  rm -rf "${INSTALL_DIR}.tmp"
  git clone --depth 1 --branch "${KUMA_VERSION}" \
    https://github.com/louislam/uptime-kuma.git "${INSTALL_DIR}.tmp" >>"${LOG}" 2>&1
  mv "${INSTALL_DIR}.tmp" "${INSTALL_DIR}"
fi

if [ ! -e "${INSTALL_DIR}/data" ]; then
  ln -s "${DATA_DIR}/data" "${INSTALL_DIR}/data"
  log "linked ${INSTALL_DIR}/data -> ${DATA_DIR}/data"
fi

if [ -f "${MARKER}" ] && [ "$(cat "${MARKER}")" = "${KUMA_VERSION}" ] && [ -d "${INSTALL_DIR}/node_modules" ]; then
  log "already installed ${KUMA_VERSION}; refreshing service only"
else
  log "npm ci + download-dist (may take several minutes; see ${LOG})"
  touch "${LOG}"
  chmod 666 "${LOG}" 2>/dev/null || true
  chown -R uptime-kuma:uptime-kuma "${INSTALL_DIR}" "${DATA_DIR}"
  sudo -u uptime-kuma env HOME="${DATA_DIR}" npm_config_cache="${DATA_DIR}/.npm" \
    bash -lc "
      set -euo pipefail
      cd '${INSTALL_DIR}'
      export NODE_ENV=production
      rm -rf node_modules
      npm ci --omit=dev --no-audit >>'${LOG}' 2>&1
      npm run download-dist >>'${LOG}' 2>&1
    "
  echo "${KUMA_VERSION}" >"${MARKER}"
  chown uptime-kuma:uptime-kuma "${MARKER}"
  log "npm install finished"
fi

cat >"${ENV_FILE}" <<EOF
# Managed by uptime-kuma-install.sh
NODE_ENV=production
KUMA_PORT=${KUMA_PORT}
KUMA_HOST=${KUMA_HOST}
EOF
chmod 0644 "${ENV_FILE}"

cat >"${SERVICE_PATH}" <<EOF
[Unit]
Description=Uptime Kuma status monitor
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=uptime-kuma
Group=uptime-kuma
WorkingDirectory=${INSTALL_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=/usr/bin/node ${INSTALL_DIR}/server/server.js --host=\${KUMA_HOST} --port=\${KUMA_PORT}
Restart=on-failure
RestartSec=10
# Ping monitors need raw ICMP sockets (Node ping module).
AmbientCapabilities=CAP_NET_RAW
CapabilityBoundingSet=CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID CAP_DAC_OVERRIDE
NoNewPrivileges=false
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now uptime-kuma
systemctl restart uptime-kuma

for i in $(seq 1 90); do
  code="$(curl -s -o /dev/null -w '%{http_code}' -m 3 "http://127.0.0.1:${KUMA_PORT}/" 2>/dev/null || echo 000)"
  if [ "${code}" = "200" ] || [ "${code}" = "302" ] || [ "${code}" = "301" ]; then
    log "HTTP ${code} on :${KUMA_PORT} (after $((i * 2))s)"
    exit 0
  fi
  sleep 2
done

log "ERROR: not responding on :${KUMA_PORT} after 180s" >&2
systemctl --no-pager status uptime-kuma >&2 || true
journalctl -u uptime-kuma --no-pager -n 40 >&2 || true
exit 1
