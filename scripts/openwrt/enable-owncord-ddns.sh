#!/bin/sh
# DDNS for owncord-pundef.mooo.com on OpenWrt (FreeDNS dynamic update URL).
# 1) Create A record on https://freedns.afraid.org (subdomain owncord-pundef, mooo.com).
# 2) Copy Dynamic update URL from the subdomain page.
# 3) Run: OWNCORD_DDNS_URL='https://freedns.afraid.org/dynamic/update.php?...' sh enable-owncord-ddns.sh
set -e

DOMAIN=owncord-pundef.mooo.com
URL="${OWNCORD_DDNS_URL:-}"

if [ -z "$URL" ]; then
  echo "[enable-owncord-ddns] set OWNCORD_DDNS_URL to FreeDNS dynamic update URL" >&2
  exit 1
fi

if uci show ddns 2>/dev/null | grep -q "ddns.owncord_pundef"; then
  uci set ddns.owncord_pundef.update_url="$URL"
else
  uci set ddns.owncord_pundef=service
  uci set ddns.owncord_pundef.enabled='1'
  uci set ddns.owncord_pundef.update_url="$URL"
  uci set ddns.owncord_pundef.lookup_host="$DOMAIN"
  uci set ddns.owncord_pundef.domain="$DOMAIN"
  uci set ddns.owncord_pundef.use_ipv6='0'
  uci set ddns.owncord_pundef.use_https='1'
  uci set ddns.owncord_pundef.cacert='IGNORE'
  uci set ddns.owncord_pundef.ip_source='web'
  uci set ddns.owncord_pundef.ip_url='https://checkip.amazonaws.com/'
  uci set ddns.owncord_pundef.interface='wan'
  uci set ddns.owncord_pundef.check_interval='10'
  uci set ddns.owncord_pundef.check_unit='minutes'
  uci set ddns.owncord_pundef.force_interval='72'
  uci set ddns.owncord_pundef.force_unit='hours'
  uci set ddns.owncord_pundef.dns_server='8.8.8.8'
fi
uci commit ddns
/etc/init.d/ddns reload
echo "[enable-owncord-ddns] configured $DOMAIN"
