#!/bin/sh
# beszel-agent-install.sh — Beszel Agent on postmarketOS / Alpine (OpenRC).
#
# Run on phoneserver as root (or via sudo). Reads /tmp/beszel-agent.env:
#   KEY, TOKEN, HUB_URL, optional LISTEN (default 45876).
#
# Idempotent. arm64 tarball must be at /tmp/beszel-agent_linux_arm64.tar.gz
# (or set BESZEL_TARBALL).

set -eu

ENV_FILE_STAGING="/tmp/beszel-agent.env"
if [ -f "${ENV_FILE_STAGING}" ]; then
    # shellcheck disable=SC1090
    . "${ENV_FILE_STAGING}"
fi

: "${KEY:?KEY (hub public SSH key) is required}"
: "${TOKEN:?TOKEN is required}"
: "${HUB_URL:?HUB_URL is required}"
LISTEN="${LISTEN:-45876}"

TARBALL="${BESZEL_TARBALL:-/tmp/beszel-agent_linux_arm64.tar.gz}"
BIN_NAME="${BESZEL_BIN_NAME:-beszel-agent}"
INSTALL_DIR="/opt/beszel-agent"
DATA_DIR="/var/lib/beszel-agent"
BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
CONF_FILE="/etc/conf.d/beszel-agent"
INIT_SCRIPT="/etc/init.d/beszel-agent"

if [ ! -f "${TARBALL}" ]; then
    echo "[beszel-agent-install] missing tarball: ${TARBALL}" >&2
    exit 1
fi

echo "[beszel-agent-install] starting"
echo "[beszel-agent-install] HUB_URL=${HUB_URL}"
echo "[beszel-agent-install] LISTEN=${LISTEN}"

apk add --no-cache tar ca-certificates iproute2 >/dev/null 2>&1 || true

if ! id beszel-agent >/dev/null 2>&1; then
    adduser -D -H -s /sbin/nologin beszel-agent
    echo "[beszel-agent-install] created user beszel-agent"
fi

install -d -m 750 -o beszel-agent -g beszel-agent "${INSTALL_DIR}"
install -d -m 750 -o beszel-agent -g beszel-agent "${DATA_DIR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT INT HUP
tar -xzf "${TARBALL}" -C "${TMPDIR}" "${BIN_NAME}"
install -m 755 -o beszel-agent -g beszel-agent "${TMPDIR}/${BIN_NAME}" "${BIN_PATH}"
echo "[beszel-agent-install] installed ${BIN_PATH}"

umask 027
cat > "${CONF_FILE}" <<EOF
# Managed by beszel-agent-install.sh — per-system TOKEN secret.
export KEY="${KEY}"
export TOKEN="${TOKEN}"
export HUB_URL="${HUB_URL}"
export LISTEN="${LISTEN}"
EOF
chown root:beszel-agent "${CONF_FILE}"
chmod 0640 "${CONF_FILE}"

cat > "${INIT_SCRIPT}" <<'INIT'
#!/sbin/openrc-run

name="beszel-agent"
description="Beszel monitoring agent"

command="/opt/beszel-agent/beszel-agent"
command_user="beszel-agent:beszel-agent"
command_background="yes"
pidfile="/run/beszel-agent.pid"
directory="/var/lib/beszel-agent"
supervisor="supervise-daemon"
respawn_delay="5"
respawn_max="0"
output_log="/var/log/beszel-agent.log"
error_log="/var/log/beszel-agent.log"

depend() {
    need phoneserver-wifi net
    after phoneserver-wifi
}

start_pre() {
    checkpath --file --owner beszel-agent:beszel-agent --mode 0644 /var/log/beszel-agent.log
    [ -x /usr/local/sbin/beszel-battery-status-fix.sh ] && /usr/local/sbin/beszel-battery-status-fix.sh
    if [ -f /etc/conf.d/beszel-agent ]; then
        # shellcheck disable=SC1091
        . /etc/conf.d/beszel-agent
    fi
}
INIT

chmod 0755 "${INIT_SCRIPT}"

if [ -f /tmp/beszel-battery-status-fix.sh ]; then
    install -d -m 755 /usr/local/sbin
    install -m 755 /tmp/beszel-battery-status-fix.sh /usr/local/sbin/beszel-battery-status-fix.sh
fi
/usr/local/sbin/beszel-battery-status-fix.sh 2>/dev/null || true

rc-update add beszel-agent default 2>/dev/null || true
rc-service beszel-agent restart

LISTEN_PORT="${LISTEN##*:}"
i=1
while [ "${i}" -le 25 ]; do
    if grep -qE 'WebSocket connected' /var/log/beszel-agent.log 2>/dev/null; then
        echo "[beszel-agent-install] WebSocket connected (after ${i}s)"
        rm -f "${ENV_FILE_STAGING}"
        exit 0
    fi
    if ss -ltn 2>/dev/null | grep -q ":${LISTEN_PORT} "; then
        echo "[beszel-agent-install] listening on :${LISTEN_PORT} (SSH mode, after ${i}s)"
        rm -f "${ENV_FILE_STAGING}"
        exit 0
    fi
    sleep 1
    i=$((i + 1))
done

echo "[beszel-agent-install] ERROR: agent not ready after 25s" >&2
rc-service beszel-agent status >&2 || true
tail -30 /var/log/beszel-agent.log >&2 || true
exit 1
