#!/bin/sh
# uptime-kuma-install.sh — Uptime Kuma on postmarketOS / Alpine (OpenRC).
#
# Run on phoneserver as root (or via sudo). Idempotent.
# Env (optional): KUMA_VERSION, KUMA_PORT, KUMA_HOST

set -eu

KUMA_VERSION="${KUMA_VERSION:-2.3.2}"
KUMA_PORT="${KUMA_PORT:-3001}"
KUMA_HOST="${KUMA_HOST:-0.0.0.0}"

INSTALL_DIR="/opt/uptime-kuma"
DATA_DIR="/var/lib/uptime-kuma"
CONF_FILE="/etc/conf.d/uptime-kuma"
INIT_SCRIPT="/etc/init.d/uptime-kuma"
MARKER="${INSTALL_DIR}/.install-version"
LOG="/var/log/uptime-kuma-install.log"

log() {
    printf '[uptime-kuma-install] %s\n' "$*"
    printf '[uptime-kuma-install] %s\n' "$*" >>"${LOG}"
}

need_node_major=20

log "starting (version ${KUMA_VERSION}, listen ${KUMA_HOST}:${KUMA_PORT})"

# No RTC battery on joyeuse — wrong clock breaks git/npm TLS until chrony steps.
if command -v chronyc >/dev/null 2>&1; then
    chronyc makestep >/dev/null 2>&1 || rc-service chronyd restart >/dev/null 2>&1 || true
    sleep 2
fi
log "system time: $(date -Iseconds 2>/dev/null || date)"

apk add --no-cache nodejs npm git curl ca-certificates python3 make g++ >/dev/null 2>&1 || \
    apk add --no-cache nodejs npm git curl ca-certificates python3 make g++ >>"${LOG}" 2>&1

if ! command -v node >/dev/null 2>&1; then
    log "ERROR: node not found after apk add" >&2
    exit 1
fi

node_major="$(node -p "Number(process.versions.node.split('.')[0])")"
if [ "${node_major}" -lt "${need_node_major}" ]; then
    log "ERROR: node $(node -v) is too old; Uptime Kuma ${KUMA_VERSION} needs >= ${need_node_major}" >&2
    exit 1
fi
log "node $(node -v), npm $(npm -v)"

if ! id uptime-kuma >/dev/null 2>&1; then
    adduser -D -H -h "${DATA_DIR}" -s /sbin/nologin uptime-kuma
    log "created user uptime-kuma"
else
    usermod -d "${DATA_DIR}" -H uptime-kuma 2>/dev/null || true
fi

install -d -m 750 -o uptime-kuma -g uptime-kuma "${DATA_DIR}/data" "${DATA_DIR}/.npm"

if [ ! -d "${INSTALL_DIR}/.git" ]; then
    log "cloning louislam/uptime-kuma ${KUMA_VERSION} (shallow; may take a minute)"
    rm -rf "${INSTALL_DIR}.tmp"
    git clone --depth 1 --branch "${KUMA_VERSION}" \
        https://github.com/louislam/uptime-kuma.git "${INSTALL_DIR}.tmp" >>"${LOG}" 2>&1
    mv "${INSTALL_DIR}.tmp" "${INSTALL_DIR}"
fi

if [ ! -L "${INSTALL_DIR}/data" ] && [ ! -d "${INSTALL_DIR}/data" ]; then
    ln -s "${DATA_DIR}/data" "${INSTALL_DIR}/data"
    log "linked ${INSTALL_DIR}/data -> ${DATA_DIR}/data"
fi

if [ -f "${MARKER}" ] && [ "$(cat "${MARKER}")" = "${KUMA_VERSION}" ] && [ -d "${INSTALL_DIR}/node_modules" ]; then
    log "already installed ${KUMA_VERSION}; refreshing service only"
else
    log "npm ci + download-dist (5–15 min on phone; see ${LOG})"
    touch "${LOG}"
    chmod 666 "${LOG}" 2>/dev/null || true
    chown -R uptime-kuma:uptime-kuma "${INSTALL_DIR}" "${DATA_DIR}"
    su uptime-kuma -s /bin/sh -c "
        set -eu
        cd '${INSTALL_DIR}'
        export NODE_ENV=production
        export HOME='${DATA_DIR}'
        export npm_config_cache='${DATA_DIR}/.npm'
        rm -rf node_modules
        npm ci --omit=dev --no-audit >>'${LOG}' 2>&1
        npm run download-dist >>'${LOG}' 2>&1
    "
    echo "${KUMA_VERSION}" >"${MARKER}"
    chown uptime-kuma:uptime-kuma "${MARKER}"
    log "npm install finished"
fi

cat >"${CONF_FILE}" <<EOF
# Managed by uptime-kuma-install.sh
export NODE_ENV=production
export KUMA_PORT=${KUMA_PORT}
export KUMA_HOST=${KUMA_HOST}
EOF
chmod 0644 "${CONF_FILE}"

cat >"${INIT_SCRIPT}" <<'INIT'
#!/sbin/openrc-run

name="uptime-kuma"
description="Uptime Kuma status monitor"

: "${command:=/usr/bin/node}"
: "${command_args:=/opt/uptime-kuma/server/server.js}"
command_background="yes"
command_user="uptime-kuma:uptime-kuma"
pidfile="/run/uptime-kuma.pid"
directory="/opt/uptime-kuma"
supervisor="supervise-daemon"
respawn_delay="10"
respawn_max="0"
output_log="/var/log/uptime-kuma.log"
error_log="/var/log/uptime-kuma.log"

depend() {
    need net
}

start_pre() {
    checkpath --file --owner uptime-kuma:uptime-kuma --mode 0644 /var/log/uptime-kuma.log
    if [ -f /etc/conf.d/uptime-kuma ]; then
        # shellcheck disable=SC1091
        . /etc/conf.d/uptime-kuma
    fi
    command_args="/opt/uptime-kuma/server/server.js --host=${KUMA_HOST:-0.0.0.0} --port=${KUMA_PORT:-3001}"
}
INIT

chmod 0755 "${INIT_SCRIPT}"

rc-update add uptime-kuma default 2>/dev/null || true
rc-service uptime-kuma restart

i=1
while [ "${i}" -le 90 ]; do
    code="$(curl -s -o /dev/null -w '%{http_code}' -m 3 "http://127.0.0.1:${KUMA_PORT}/" 2>/dev/null || echo 000)"
    if [ "${code}" = "200" ] || [ "${code}" = "302" ] || [ "${code}" = "301" ]; then
        log "HTTP ${code} on :${KUMA_PORT} (after $((i * 2))s)"
        log "open http://<phone-ip>:${KUMA_PORT}/ and create the admin account"
        exit 0
    fi
    sleep 2
    i=$((i + 1))
done

log "ERROR: not responding on :${KUMA_PORT} after 180s" >&2
rc-service uptime-kuma status >&2 || true
tail -40 /var/log/uptime-kuma.log >&2 || true
exit 1
