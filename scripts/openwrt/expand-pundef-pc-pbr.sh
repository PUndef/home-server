#!/bin/sh
# DEPRECATED — superseded by apply-pundef-pc-routes.sh (generated from manifest).
# Add pundef-pc WiFi + srv (Mercusys) IPs to all "pundef-pc *" pbr policies.
# Without this, traffic from 192.168.1.208 / 192.168.50.133 bypasses games/steam policies.
#
# Usage:
#   sh expand-pundef-pc-pbr.sh
#   WARFRAME_PC_IP=192.168.1.133 WARFRAME_PC_IP2=192.168.1.208 PUNDEF_PC_SRV=192.168.50.133 sh expand-pundef-pc-pbr.sh

set -eu

PC_ETH="${WARFRAME_PC_IP:-192.168.1.133}"
PC_WIFI="${WARFRAME_PC_IP2:-192.168.1.208}"
PC_SRV="${PUNDEF_PC_SRV:-192.168.50.133}"

updated=0
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  case "${name}" in
    pundef-pc\ *)
      uci delete "pbr.@policy[${i}].src_addr" 2>/dev/null || true
      uci add_list "pbr.@policy[${i}].src_addr=${PC_ETH}/32"
      uci add_list "pbr.@policy[${i}].src_addr=${PC_WIFI}/32"
      uci add_list "pbr.@policy[${i}].src_addr=${PC_SRV}/32"
      echo "[expand-pundef-pc-pbr] ${name} -> src ${PC_ETH} ${PC_WIFI} ${PC_SRV}"
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
