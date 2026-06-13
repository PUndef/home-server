#!/bin/sh
# Pin phoneserver interfaces to fixed IPs on OpenWrt.
#
#   eth0 (USB-Ethernet hub → srv / lan2): 192.168.50.127  MAC dc:04:5a:58:5a:93
#   wlan0 (2.4 GHz, Voice PE / Groq lan path): 192.168.1.227  MAC 22:84:8d:3d:5d:8e
#
# Run on the router as root, or via:
#   ssh root@192.168.1.1 'sh -s' < reserve-phoneserver-dhcp.sh

set -eu

reserve_host() {
  name="$1"
  mac="$2"
  ip="$3"

  idx=""
  i=0
  mac_lc="$(echo "${mac}" | tr 'A-Z' 'a-z')"
  while uci -q get "dhcp.@host[${i}]" >/dev/null 2>&1; do
    existing_mac="$(uci -q get "dhcp.@host[${i}].mac" | tr 'A-Z' 'a-z')"
    existing_name="$(uci -q get "dhcp.@host[${i}].name" 2>/dev/null || true)"
    if [ "${existing_mac}" = "${mac_lc}" ] || [ "${existing_name}" = "${name}" ]; then
      idx="${i}"
      break
    fi
    i=$((i + 1))
  done

  if [ -z "${idx}" ]; then
    uci add dhcp host >/dev/null
    idx="${i}"
  fi

  uci set "dhcp.@host[${idx}].name=${name}"
  uci set "dhcp.@host[${idx}].mac=${mac_lc}"
  uci set "dhcp.@host[${idx}].ip=${ip}"
  uci set "dhcp.@host[${idx}].leasetime=infinite"
  echo "[reserve-phoneserver-dhcp] ${name} ${mac_lc} -> ${ip} (infinite)"
}

# srv segment (Mercusys hub → X3000T lan2)
reserve_host "${PHONESERVER_SRV_NAME:-phoneserver}" \
  "${PHONESERVER_SRV_MAC:-dc:04:5a:58:5a:93}" \
  "${PHONESERVER_SRV_IP:-192.168.50.127}"

# lan Wi-Fi — HA internal_url for Voice PE, Groq PBR src
reserve_host "${PHONESERVER_WLAN_NAME:-phoneserver-wlan}" \
  "${PHONESERVER_WLAN_MAC:-22:84:8d:3d:5d:8e}" \
  "${PHONESERVER_WLAN_IP:-192.168.1.227}"

uci commit dhcp
/etc/init.d/dnsmasq restart

echo "[reserve-phoneserver-dhcp] done"
