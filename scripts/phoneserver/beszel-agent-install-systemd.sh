#!/bin/bash
# Beszel agent on postmarketOS v25.12 (systemd). Reads /tmp/beszel-agent.env
set -eu

ENV_FILE_STAGING="/tmp/beszel-agent.env"
if [ -f "$ENV_FILE_STAGING" ]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE_STAGING"
fi

: "${KEY:?KEY required}"
: "${TOKEN:?TOKEN required}"
: "${HUB_URL:?HUB_URL required}"
LISTEN="${LISTEN:-45876}"

TARBALL="${BESZEL_TARBALL:-/tmp/beszel-agent_linux_arm64.tar.gz}"
BIN_NAME="${BESZEL_BIN_NAME:-beszel-agent}"
INSTALL_DIR="/opt/beszel-agent"
DATA_DIR="/var/lib/beszel-agent"
BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
ENV_FILE="/etc/default/beszel-agent"
SERVICE_PATH="/etc/systemd/system/beszel-agent.service"

[ -f "$TARBALL" ] || { echo "missing $TARBALL" >&2; exit 1; }

echo "[beszel-systemd] HUB_URL=$HUB_URL LISTEN=$LISTEN"

if ! id beszel-agent >/dev/null 2>&1; then
    adduser -D -H -s /sbin/nologin beszel-agent
fi
if getent group docker >/dev/null 2>&1; then
    addgroup beszel-agent docker 2>/dev/null || true
fi

install -d -m 750 -o beszel-agent -g beszel-agent "$INSTALL_DIR" "$DATA_DIR"
install -d -m 755 /etc/default
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT
tar -xzf "$TARBALL" -C "$TMPDIR" "$BIN_NAME"
install -m 755 -o beszel-agent -g beszel-agent "$TMPDIR/$BIN_NAME" "$BIN_PATH"

umask 027
cat > "$ENV_FILE" <<EOF
KEY="${KEY}"
TOKEN=${TOKEN}
HUB_URL=${HUB_URL}
LISTEN=${LISTEN}
EOF
chown root:beszel-agent "$ENV_FILE"
chmod 0640 "$ENV_FILE"

if [ -f /tmp/beszel-battery-status-fix.sh ]; then
    install -m 755 /tmp/beszel-battery-status-fix.sh /usr/local/sbin/beszel-battery-status-fix.sh
fi

cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Beszel Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=beszel-agent
Group=beszel-agent
WorkingDirectory=${DATA_DIR}
EnvironmentFile=${ENV_FILE}
ExecStartPre=-/usr/local/sbin/beszel-battery-status-fix.sh
ExecStart=${BIN_PATH}
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now beszel-agent

for i in $(seq 1 25); do
    if journalctl -u beszel-agent --no-pager -n 30 2>/dev/null | grep -qE 'WebSocket connected|listening on'; then
        echo "[beszel-systemd] ready after ${i}s"
        journalctl -u beszel-agent --no-pager -n 8
        rm -f "$ENV_FILE_STAGING"
        exit 0
    fi
    sleep 1
done

echo "[beszel-systemd] not ready" >&2
journalctl -u beszel-agent --no-pager -n 20 >&2
exit 1
