#!/bin/sh
# Pin phoneserver (postmarketOS on Redmi joyeuse) to a fixed IP on OpenWrt.
# phoneserver eth0 (USB-Ethernet hub) plugs into srv segment (Mercusys -> lan2).
#
# Run on the router as root, or via: ssh root@192.168.1.1 'sh -s' < reserve-phoneserver-dhcp.sh
#
# USB-Ethernet hub MAC: dc:04:5a:58:5a:93

set -eu

NAME="${PHONESERVER_DHCP_NAME:-phoneserver}"
MAC="${PHONESERVER_MAC:-dc:04:5a:58:5a:93}"
IP="${PHONESERVER_IP:-192.168.50.127}"

idx=""
i=0
while uci -q get "dhcp.@host[${i}]" >/dev/null 2>&1; do
    existing_mac="$(uci -q get "dhcp.@host[${i}].mac" | tr 'A-Z' 'a-z')"
    existing_name="$(uci -q get "dhcp.@host[${i}].name" 2>/dev/null || true)"
    if [ "${existing_mac}" = "$(echo "${MAC}" | tr 'A-Z' 'a-z')" ] || \
       [ "${existing_name}" = "${NAME}" ] || \
       [ "${existing_name}" = "Redmi-Note-9-Pro" ]; then
        idx="${i}"
        break
    fi
    i=$((i + 1))
done

if [ -z "${idx}" ]; then
    uci add dhcp host >/dev/null
    idx="${i}"
fi

uci set "dhcp.@host[${idx}].name=${NAME}"
uci set "dhcp.@host[${idx}].mac=${MAC}"
uci set "dhcp.@host[${idx}].ip=${IP}"
uci set "dhcp.@host[${idx}].leasetime=infinite"
uci commit dhcp
/etc/init.d/dnsmasq restart

echo "[reserve-phoneserver-dhcp] ${NAME} ${MAC} -> ${IP} (infinite)"
