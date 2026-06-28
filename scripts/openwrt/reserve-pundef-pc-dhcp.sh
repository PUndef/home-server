#!/bin/sh
# Pin pundef-pc interfaces to fixed IPs on OpenWrt.
#
#   eth lan (X3000T lan3/lan4): 192.168.1.133  MAC 9c:6b:00:8b:3f:18
#   wlan lan:                   192.168.1.208  (same host, Wi‑Fi NIC — set PUNDEF_PC_WLAN_MAC)
#   eth srv (Mercusys → lan2):  192.168.50.133 MAC 9c:6b:00:8b:3f:18
#
# Run on the router as root, or via:
#   ssh root@192.168.1.1 'sh -s' < reserve-pundef-pc-dhcp.sh

set -eu

reserve_host() {
  name="$1"
  mac="$2"
  ip="$3"
  section="$4"

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
  if [ -n "${section}" ]; then
    uci set "dhcp.@host[${idx}].tag=${section}"
  else
    uci delete "dhcp.@host[${idx}].tag" 2>/dev/null || true
  fi
  echo "[reserve-pundef-pc-dhcp] ${name} ${mac_lc} -> ${ip} (${section:-default})"
}

LAN_MAC="${PUNDEF_PC_LAN_MAC:-9c:6b:00:8b:3f:18}"
WLAN_MAC="${PUNDEF_PC_WLAN_MAC:-}"
LAN_IP="${PUNDEF_PC_LAN_IP:-192.168.1.133}"
WLAN_IP="${PUNDEF_PC_WLAN_IP:-192.168.1.208}"
SRV_IP="${PUNDEF_PC_SRV_IP:-192.168.50.133}"

# lan segment (direct to X3000T lan ports / Wi‑Fi)
reserve_host "${PUNDEF_PC_LAN_NAME:-pundef-pc}" "${LAN_MAC}" "${LAN_IP}" "lan"

if [ -n "${WLAN_MAC}" ]; then
  reserve_host "${PUNDEF_PC_WLAN_NAME:-pundef-pc-wifi}" "${WLAN_MAC}" "${WLAN_IP}" "lan"
fi

# srv segment (Mercusys switch → X3000T lan2)
reserve_host "${PUNDEF_PC_SRV_NAME:-pundef-pc-srv}" "${LAN_MAC}" "${SRV_IP}" "srv"

uci commit dhcp
/etc/init.d/dnsmasq restart

echo "[reserve-pundef-pc-dhcp] done"
