#!/usr/bin/env bash
# beszel-hub-install.sh
#
# Installs the Beszel Hub binary and a systemd unit inside a Debian-based
# LXC. Designed for LXC 102 (static-sites) but is generic - any Debian/Ubuntu
# system with systemd will work.
#
# Idempotent: re-running upgrades the binary in place and reloads the unit.
#
# After install:
#   - hub listens on 127.0.0.1:8090 (Caddy proxies it, no public exposure)
#   - data lives in /opt/beszel/pb_data (PocketBase SQLite)
#   - service: `systemctl status beszel`

set -euo pipefail

BESZEL_VERSION="0.18.7"
TARBALL="beszel_linux_amd64.tar.gz"
URL="https://github.com/henrygd/beszel/releases/download/v${BESZEL_VERSION}/${TARBALL}"

# Pre-staged tarball path. If it exists, we skip the network download.
# This is needed in environments where direct egress to github.com is
# blocked by the router (srv-segment cannot use awg1, and github falls
# under the AI/Cursor pbr-policy on OpenWrt). Operator can drop the
# tarball into /tmp/ via `pct push`, then run this script.
PRESTAGED_TARBALL="${BESZEL_TARBALL:-/tmp/${TARBALL}}"

INSTALL_DIR="/opt/beszel"
DATA_DIR="${INSTALL_DIR}/pb_data"
BIN_PATH="${INSTALL_DIR}/beszel"
SERVICE_PATH="/etc/systemd/system/beszel.service"

LISTEN_ADDR="127.0.0.1:8090"

# Public URL of the hub. The path component (e.g. /beszel) is auto-derived
# by Beszel as BASE_PATH for the frontend, so SPA assets and API calls go
# to the right URL when reverse-proxied under a subpath. Override via env:
#   APP_URL=https://example.com/beszel bash beszel-hub-install.sh
APP_URL="${APP_URL:-https://apps-pundef.mooo.com/beszel}"

echo "[beszel-hub-install] starting installation (v${BESZEL_VERSION})"
echo "[beszel-hub-install] APP_URL=${APP_URL}"

apt-get update -qq
apt-get install -y -qq tar ca-certificates iproute2

if ! id beszel >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin beszel
    echo "[beszel-hub-install] created system user 'beszel'"
fi

install -d -m 750 -o beszel -g beszel "${INSTALL_DIR}"
install -d -m 750 -o beszel -g beszel "${DATA_DIR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT

if [[ -f "${PRESTAGED_TARBALL}" ]]; then
    echo "[beszel-hub-install] using pre-staged tarball: ${PRESTAGED_TARBALL}"
    cp "${PRESTAGED_TARBALL}" "${TMPDIR}/${TARBALL}"
else
    echo "[beszel-hub-install] downloading ${URL}"
    apt-get install -y -qq curl
    curl -fsSL -o "${TMPDIR}/${TARBALL}" "${URL}"
fi

tar -xzf "${TMPDIR}/${TARBALL}" -C "${TMPDIR}" beszel
install -m 755 -o beszel -g beszel "${TMPDIR}/beszel" "${BIN_PATH}"
echo "[beszel-hub-install] installed binary at ${BIN_PATH}"

cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Beszel Hub
After=network.target

[Service]
Type=simple
User=beszel
Group=beszel
WorkingDirectory=${INSTALL_DIR}
Environment="APP_URL=${APP_URL}"
ExecStart=${BIN_PATH} serve --http "${LISTEN_ADDR}"
Restart=always
RestartSec=5
LimitNOFILE=4096

# light hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now beszel
systemctl restart beszel

for i in $(seq 1 15); do
    if ss -ltn | grep -q ':8090 '; then
        echo "[beszel-hub-install] beszel listening on ${LISTEN_ADDR} (after ${i}s)"
        exit 0
    fi
    sleep 1
done

echo "[beszel-hub-install] ERROR: beszel did not start listening on ${LISTEN_ADDR}" >&2
systemctl --no-pager --full status beszel >&2 || true
journalctl -u beszel --no-pager -n 50 >&2 || true
exit 1
