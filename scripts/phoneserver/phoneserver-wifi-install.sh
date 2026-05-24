#!/bin/sh
# phoneserver-wifi-install.sh — autostart Wi-Fi on boot (OpenRC).
# Run on phoneserver as root. Idempotent.

set -eu

INSTALL_SRC="${PHONESERVER_WIFI_INIT:-/tmp/phoneserver-wifi.initd}"
INIT="/etc/init.d/phoneserver-wifi"
CONF="/etc/conf.d/phoneserver-wifi"
LOG="/var/log/phoneserver-wifi.log"

log() { printf '[phoneserver-wifi-install] %s\n' "$*"; }

if [ ! -f "${INSTALL_SRC}" ]; then
    log "ERROR: missing ${INSTALL_SRC}" >&2
    exit 1
fi

install -m 755 "${INSTALL_SRC}" "${INIT}"

if [ ! -f "${CONF}" ]; then
    cat >"${CONF}" <<'EOF'
# Managed by phoneserver-wifi-install.sh
WIFI_IFACE=wlan0
WIFI_RETRIES=18
WIFI_RETRY_DELAY=5
WIFI_SSID_EXPECT=DECO_HOME
EOF
fi

# beszel-agent: wait for Wi-Fi bring-up
BESZEL_INIT="/etc/init.d/beszel-agent"
if [ -f "${BESZEL_INIT}" ] && ! grep -q phoneserver-wifi "${BESZEL_INIT}"; then
    sed -i 's/need net/need phoneserver-wifi net/' "${BESZEL_INIT}"
    sed -i 's/after networking/after phoneserver-wifi/' "${BESZEL_INIT}"
fi

# uptime-kuma: same
KUMA_INIT="/etc/init.d/uptime-kuma"
if [ -f "${KUMA_INIT}" ] && ! grep -q phoneserver-wifi "${KUMA_INIT}"; then
    sed -i 's/need net/need phoneserver-wifi net/' "${KUMA_INIT}" 2>/dev/null || true
    sed -i 's/after networking/after phoneserver-wifi/' "${KUMA_INIT}" 2>/dev/null || true
    sed -i 's/after phoneserver-wifi phoneserver-wifi/after phoneserver-wifi/' "${KUMA_INIT}" 2>/dev/null || true
fi

touch "${LOG}"
chmod 644 "${LOG}"

rc-update add phoneserver-wifi default 2>/dev/null || true
rc-service phoneserver-wifi restart

if ip -4 -o addr show dev wlan0 2>/dev/null | grep -q 'inet '; then
    log "wlan0 has IPv4 — ok"
    ip -4 addr show wlan0 | grep inet
    rc-service beszel-agent restart 2>/dev/null || true
    rc-service uptime-kuma restart 2>/dev/null || true
    exit 0
fi

log "WARN: wlan0 still down — check ${LOG} and /var/log/phoneserver-wifi.log after reboot" >&2
exit 1
