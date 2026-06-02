#!/bin/sh
# Remove OwnCord split-horizon line from /etc/dnsmasq.conf
set -e

DOMAIN="${OWNCORD_DOMAIN:-owncord-pundef.mooo.com}"
sed -i "/${DOMAIN}/d" /etc/dnsmasq.conf
/etc/init.d/dnsmasq restart
echo "[disable-owncord-dns] removed ${DOMAIN}"
