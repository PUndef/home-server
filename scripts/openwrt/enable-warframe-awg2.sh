#!/bin/sh
# DEPRECATED — superseded by manifest pbr_baseline.warframe + apply_overrides.py.
# Route Warframe / Soulframe traffic via primary AmneziaWG tunnel (awg2 by default).
# - Global policy: game-related domains -> primary tunnel (all LAN clients).
# PC-specific routes (Steam WAN, Destiny, Nexus, Discord DNS) — apply-pundef-pc-routes.sh.
# This script only maintains the global Warframe domain policy.
#
# Run on router: sh enable-warframe-awg2.sh
# Or from PC: ssh root@192.168.1.1 'sh -s' < enable-warframe-awg2.sh

set -eu

PRIMARY="$(uci -q get podkop.main.interface 2>/dev/null || true)"
case "${PRIMARY}" in
  awg1|awg2) ;;
  *) PRIMARY=awg2 ;;
esac

if ! ifstatus "${PRIMARY}" | grep -q '"up": true'; then
  echo "[enable-warframe-awg2] ERROR: ${PRIMARY} is down — aborting"
  exit 1
fi

GLOBAL_POLICY="Warframe via ${PRIMARY}"

# Launcher/API/CDN; chat often uses IPs resolved outside these names — PC policy covers that.
GAME_DOMAINS="warframe.com *.warframe.com api.warframe.com content.warframe.com \
  soulframe.com *.soulframe.com digitalextremes.com *.digitalextremes.com"

upsert_policy() {
  policy_name="$1"
  iface="$2"
  dest_list="$3"

  idx=""
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    existing_name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    if [ "${existing_name}" = "${policy_name}" ]; then
      idx="${i}"
      break
    fi
    i=$((i + 1))
  done
  if [ -z "${idx}" ]; then
    uci add pbr policy >/dev/null
    idx="${i}"
  fi

  uci set "pbr.@policy[${idx}].name=${policy_name}"
  uci set "pbr.@policy[${idx}].interface=${iface}"
  uci set "pbr.@policy[${idx}].enabled=1"

  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  for d in ${dest_list}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done

  echo "[enable-warframe-awg2] policy ${policy_name} -> ${iface} (idx ${idx})"
}

echo "=== enable Warframe/Soulframe via ${PRIMARY} ==="

upsert_policy "${GLOBAL_POLICY}" "${PRIMARY}" "${GAME_DOMAINS}"
delete_games=0
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  case "${name}" in
    "pundef-pc games via "*) uci delete "pbr.@policy[${i}]"; delete_games=1; i=0; continue ;;
  esac
  i=$((i + 1))
done
[ "${delete_games}" -eq 1 ] && echo "[enable-warframe-awg2] removed catch-all ${PC_POLICY:-games}"

uci commit pbr
/etc/init.d/pbr restart

echo "=== done; wait ~15s then: nslookup warframe.com 192.168.1.1; trace / test in-game chat ==="
