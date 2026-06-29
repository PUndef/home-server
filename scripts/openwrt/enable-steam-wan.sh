#!/bin/sh
# DEPRECATED — use apply_overrides.py --mode normal (manifest pbr_baseline.steam).
# Route Steam from pundef-pc (192.168.1.133) via WAN, bypassing games catch-all awg2.
# Policy must sit BEFORE "pundef-pc games via awg2" (0.0.0.0/0) in pbr chain.
#
# Run on router: sh enable-steam-wan.sh
# Or from PC: py -3 scripts/openwrt/switch_steam_route.py wan
# Toggle:    py -3 scripts/openwrt/switch_steam_route.py awg2  (Steam + Destiny -> tunnel)

set -eu

POLICY_NAME="pundef-pc steam via wan"
PC_IP="${STEAM_PC_IP:-192.168.1.133}"
PC_IP2="${STEAM_PC_IP2:-192.168.1.208}"
IFACE="wan"

# Store/API/CDN; *.steamstatic.com covers cdn/client-update.akamai.steamstatic.com
STEAM_DOMAINS="steampowered.com *.steampowered.com \
  steamcommunity.com *.steamcommunity.com \
  steamcontent.com *.steamcontent.com \
  steamstatic.com *.steamstatic.com \
  valvesoftware.com *.valvesoftware.com \
  steamcdn-a.akamaihd.net"

find_policy_idx() {
  name="$1"
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    existing_name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    if [ "${existing_name}" = "${name}" ]; then
      echo "${i}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

policy_count() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    i=$((i + 1))
  done
  echo "${i}"
}

last_policy_idx() {
  count="$(policy_count)"
  if [ "${count}" -eq 0 ]; then
    echo 0
  else
    echo $((count - 1))
  fi
}

upsert_policy() {
  idx=""
  if idx="$(find_policy_idx "${POLICY_NAME}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    idx="$(last_policy_idx)"
  fi

  uci set "pbr.@policy[${idx}].name=${POLICY_NAME}"
  uci set "pbr.@policy[${idx}].interface=${IFACE}"
  uci set "pbr.@policy[${idx}].enabled=1"
  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_IP}/32"
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_IP2}/32"

  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  for d in ${STEAM_DOMAINS}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done

  echo "[enable-steam-wan] policy ${POLICY_NAME} -> ${IFACE} (idx ${idx})" >&2
  echo "${idx}"
}

reorder_before_games() {
  steam_idx="$1"
  games_idx=""
  if games_idx="$(find_policy_idx "pundef-pc games via awg2" 2>/dev/null)"; then
    :
  elif games_idx="$(find_policy_idx "pundef-pc games via awg1" 2>/dev/null)"; then
    :
  else
    echo "[enable-steam-wan] WARN: games catch-all policy not found — skip reorder" >&2
    return 0
  fi

  if [ "${steam_idx}" -gt "${games_idx}" ]; then
    uci reorder "pbr.@policy[${steam_idx}]=${games_idx}"
    echo "[enable-steam-wan] reordered steam policy before games (was ${steam_idx}, now ${games_idx})" >&2
  else
    echo "[enable-steam-wan] steam policy already before games (${steam_idx} < ${games_idx})" >&2
  fi
}

echo "=== enable Steam via WAN for ${PC_IP} ==="

steam_idx="$(upsert_policy)"
reorder_before_games "${steam_idx}"

uci commit pbr
/etc/init.d/pbr restart

echo "=== done; wait ~15s then test Steam download ==="
