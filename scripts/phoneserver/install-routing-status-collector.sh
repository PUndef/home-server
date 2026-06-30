#!/bin/bash
# Install routing status collector on phoneserver (postmarketOS / systemd).
# Run on phoneserver after files are copied to /tmp/routing-status-install/.
set -eu

STAGING="${STAGING:-/tmp/routing-status-install}"
INSTALL_ROOT="/opt/home-server"
ENV_FILE="/etc/routing-status-collector.env"
SERVICE="routing-status-collector.service"
TIMER="routing-status-collector.timer"

if [ "$(id -u)" -ne 0 ]; then
  echo "run as root: sudo $0" >&2
  exit 1
fi

if [ ! -d "${STAGING}" ]; then
  echo "missing staging dir ${STAGING}" >&2
  exit 1
fi

echo "[install-routing-status] apk packages..."
apk add --no-cache python3 py3-paramiko openssh-client >/dev/null

echo "[install-routing-status] install scripts and manifest..."
install -d -m 755 "${INSTALL_ROOT}/scripts/openwrt"
install -d -m 755 "${INSTALL_ROOT}/scripts/phoneserver"
install -d -m 755 "${INSTALL_ROOT}/config/openwrt"
install -m 644 "${STAGING}/routing_status.py" "${INSTALL_ROOT}/scripts/openwrt/routing_status.py"
install -m 644 "${STAGING}/overrides.json" "${INSTALL_ROOT}/config/openwrt/overrides.json"
install -m 755 "${STAGING}/routing-status-collector.sh" "${INSTALL_ROOT}/scripts/phoneserver/routing-status-collector.sh"

install -d -m 700 /home/user/.ssh
if [ -f "${STAGING}/openwrt_collector" ]; then
  install -m 600 "${STAGING}/openwrt_collector" /home/user/.ssh/openwrt_collector
  chown user:user /home/user/.ssh/openwrt_collector
fi
if [ -f "${STAGING}/lxc_deploy_key" ]; then
  install -m 600 "${STAGING}/lxc_deploy_key" /home/user/.ssh/lxc_deploy_key
  chown user:user /home/user/.ssh/lxc_deploy_key
fi

cat > "${ENV_FILE}" <<'EOF'
INSTALL_ROOT=/opt/home-server
OPENWRT_HOST=192.168.1.1
OPENWRT_KEY=/home/user/.ssh/openwrt_collector
LXC_TARGET=deploy@192.168.50.35
LXC_KEY=/home/user/.ssh/lxc_deploy_key
LXC_DIR=/srv/static-sites/network-routing
EOF
chmod 644 "${ENV_FILE}"

install -m 644 "${STAGING}/${SERVICE}" "/etc/systemd/system/${SERVICE}"
install -m 644 "${STAGING}/${TIMER}" "/etc/systemd/system/${TIMER}"

systemctl daemon-reload
systemctl enable --now "${TIMER}"
systemctl start "${SERVICE}" || true

echo "[install-routing-status] timer status:"
systemctl status "${TIMER}" --no-pager -l || true
echo "[install-routing-status] done"
