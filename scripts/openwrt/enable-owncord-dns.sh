#!/bin/sh
# Split-horizon DNS: owncord-pundef.mooo.com -> Apache edge (nextcloud-vm).
# Запись в /etc/dnsmasq.conf — uci add_list сбрасывается при reload dnsmasq (podkop/pbr).
# Run on OpenWrt or: py -3 scripts/openwrt/openwrt_exec.py "sh /tmp/enable-owncord-dns.sh"

set -e

DOMAIN="${OWNCORD_DOMAIN:-owncord-pundef.mooo.com}"
IP="${OWNCORD_EDGE_IP:-192.168.50.34}"
LINE="address=/${DOMAIN}/${IP}"

if grep -qF "${LINE}" /etc/dnsmasq.conf 2>/dev/null; then
  echo "[enable-owncord-dns] already in /etc/dnsmasq.conf"
else
  echo "${LINE}" >>/etc/dnsmasq.conf
  echo "[enable-owncord-dns] appended ${LINE}"
fi

/etc/init.d/dnsmasq restart
echo "[enable-owncord-dns] dnsmasq restarted"
nslookup "${DOMAIN}" 127.0.0.1 2>/dev/null | grep -E 'Name:|Address:' || true
