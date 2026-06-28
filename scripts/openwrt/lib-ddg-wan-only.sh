#!/bin/sh
# Minimal fix: v3/v5.animelib.org via WAN (DDoS-Guard blocks awg2 VPN IP).
# Paste on router (SSH/LuCI terminal from Wi‑Fi 192.168.1.x):
#   sh /tmp/lib-ddg-wan-only.sh
#
# Or from PC on lan/Wi‑Fi:
#   py -3 scripts/openwrt/openwrt_exec.py "sh -s" < scripts/openwrt/lib-ddg-wan-only.sh

set -eu

POLICY="pundef-pc lib ddg via wan"
PC_ETH="${PUNDEF_PC_ETH:-192.168.1.133}"
PC_WIFI="${PUNDEF_PC_WIFI:-192.168.1.208}"
PC_SRV="${PUNDEF_PC_SRV:-192.168.50.133}"
DOMAINS="v3.animelib.org v5.animelib.org"

find_idx() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    if [ "$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)" = "${POLICY}" ]; then
      echo "${i}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

count_policies() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    i=$((i + 1))
  done
  echo "${i}"
}

echo "=== ${POLICY} ==="

if ! idx="$(find_idx)"; then
  uci add pbr policy >/dev/null
  idx=$(( $(count_policies) - 1 ))
fi

uci set "pbr.@policy[${idx}].name=${POLICY}"
uci set "pbr.@policy[${idx}].interface=wan"
uci set "pbr.@policy[${idx}].enabled=1"
uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
uci add_list "pbr.@policy[${idx}].src_addr=${PC_ETH}/32"
uci add_list "pbr.@policy[${idx}].src_addr=${PC_WIFI}/32"
uci add_list "pbr.@policy[${idx}].src_addr=${PC_SRV}/32"
uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
for d in ${DOMAINS}; do
  uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
done

# Global fallback (other LAN clients)
GLOBAL="Lib DDG mirrors via wan"
if ! gidx="$(find_idx 2>/dev/null)"; then
  :
fi
gidx=""
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  if [ "$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)" = "${GLOBAL}" ]; then
    gidx="${i}"
    break
  fi
  i=$((i + 1))
done
if [ -z "${gidx}" ]; then
  uci add pbr policy >/dev/null
  gidx=$(( $(count_policies) - 1 ))
  uci set "pbr.@policy[${gidx}].name=${GLOBAL}"
  uci set "pbr.@policy[${gidx}].interface=wan"
  uci set "pbr.@policy[${gidx}].enabled=1"
  uci delete "pbr.@policy[${gidx}].src_addr" 2>/dev/null || true
  for d in ${DOMAINS}; do
    uci add_list "pbr.@policy[${gidx}].dest_addr=${d}"
  done
fi

# Remove *.animelib.org from Mangalib via awg* (pulls v5 into VPN)
PRIMARY="$(uci -q get podkop.main.interface 2>/dev/null || echo awg2)"
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  if [ "$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)" = "Mangalib via ${PRIMARY}" ]; then
    j=0
    while uci -q get "pbr.@policy[${i}].dest_addr[${j}]" >/dev/null 2>&1; do
      if [ "$(uci -q get "pbr.@policy[${i}].dest_addr[${j}]" 2>/dev/null || true)" = "*.animelib.org" ]; then
        uci delete "pbr.@policy[${i}].dest_addr[${j}]"
        echo "removed *.animelib.org from Mangalib via ${PRIMARY}"
        break
      fi
      j=$((j + 1))
    done
    if ! uci -q get "pbr.@policy[${i}].dest_addr" 2>/dev/null | grep -Fq "animelib.org"; then
      uci add_list "pbr.@policy[${i}].dest_addr=animelib.org"
    fi
    break
  fi
  i=$((i + 1))
done

uci commit pbr
/etc/init.d/pbr restart

echo "done — wait 15s, then from PC: curl -I https://v5.animelib.org/ (expect not 403 geoblock)"
