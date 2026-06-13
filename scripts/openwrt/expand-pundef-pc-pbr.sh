#!/bin/sh
# Add pundef-pc WiFi IP to all "pundef-pc *" pbr policies (dual-NIC: eth .133 + wlan .208).
# Without this, traffic from 192.168.1.208 bypasses games/steam policies and exits RU WAN.
#
# Usage:
#   sh expand-pundef-pc-pbr.sh
#   WARFRAME_PC_IP=192.168.1.133 WARFRAME_PC_IP2=192.168.1.208 sh expand-pundef-pc-pbr.sh

set -eu

PC_ETH="${WARFRAME_PC_IP:-192.168.1.133}"
PC_WIFI="${WARFRAME_PC_IP2:-192.168.1.208}"
SRC_ADDRS="'${PC_ETH}/32' '${PC_WIFI}/32'"

updated=0
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  case "${name}" in
    pundef-pc\ *)
      uci delete "pbr.@policy[${i}].src_addr" 2>/dev/null || true
      uci add_list "pbr.@policy[${i}].src_addr=${PC_ETH}/32"
      uci add_list "pbr.@policy[${i}].src_addr=${PC_WIFI}/32"
      echo "[expand-pundef-pc-pbr] ${name} -> src ${PC_ETH} ${PC_WIFI}"
      updated=$((updated + 1))
      ;;
  esac
  i=$((i + 1))
done

if [ "${updated}" -eq 0 ]; then
  echo "[expand-pundef-pc-pbr] no pundef-pc policies found"
  exit 1
fi

uci commit pbr
/etc/init.d/pbr restart
echo "[expand-pundef-pc-pbr] updated ${updated} policies; wait ~15s before testing"
