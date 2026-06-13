#!/bin/sh
# Route Nexus Mods from pundef-pc (192.168.1.133) via WAN, bypassing games catch-all awg2.
# Policy must sit BEFORE "pundef-pc games via awg2" (0.0.0.0/0) in pbr chain.
#
# Run on router: sh enable-nexus-wan.sh
# Or from PC: ssh root@192.168.1.1 'sh -s' < enable-nexus-wan.sh

set -eu

POLICY_NAME="pundef-pc nexus via wan"
PC_IP="${NEXUS_PC_IP:-192.168.1.133}"
PC_IP2="${NEXUS_PC_IP2:-192.168.1.208}"
IFACE="wan"

# Site + CDN/API; *.nexusmods.com covers staticdelivery/data/users/etc.
NEXUS_DOMAINS="nexusmods.com *.nexusmods.com"

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
  for d in ${NEXUS_DOMAINS}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done

  echo "[enable-nexus-wan] policy ${POLICY_NAME} -> ${IFACE} (idx ${idx})" >&2
  echo "${idx}"
}

reorder_before_games() {
  nexus_idx="$1"
  games_idx=""
  if games_idx="$(find_policy_idx "pundef-pc games via awg2" 2>/dev/null)"; then
    :
  elif games_idx="$(find_policy_idx "pundef-pc games via awg1" 2>/dev/null)"; then
    :
  else
    echo "[enable-nexus-wan] WARN: games catch-all policy not found — skip reorder" >&2
    return 0
  fi

  if [ "${nexus_idx}" -gt "${games_idx}" ]; then
    uci reorder "pbr.@policy[${nexus_idx}]=${games_idx}"
    echo "[enable-nexus-wan] reordered nexus policy before games (was ${nexus_idx}, now ${games_idx})" >&2
  else
    echo "[enable-nexus-wan] nexus policy already before games (${nexus_idx} < ${games_idx})" >&2
  fi
}

echo "=== enable Nexus Mods via WAN for ${PC_IP} ==="

nexus_idx="$(upsert_policy)"
reorder_before_games "${nexus_idx}"

uci commit pbr
/etc/init.d/pbr restart

echo "=== done; wait ~15s then test Nexus in browser / Vortex download ==="
