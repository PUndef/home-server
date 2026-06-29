#!/bin/sh
# Destiny login: Steam + Bungie auth via primary tunnel (awg2). Restore with destiny-normal-mode.sh
#
# Steam auth must exit non-RU IP during Destiny login (TAPIR bypass).
# https://steamcommunity.com/sharedfiles/filedetails/?id=3674136993
#
# Usage:
#   sh destiny-login-mode.sh           # Steam domains -> tunnel
#   sh destiny-login-mode.sh --full  # ALL egress .133/.208 -> tunnel (stronger)
# From PC:
#   py -3 scripts/openwrt/apply_overrides.py --mode login
#   py -3 scripts/openwrt/apply_overrides.py --mode login --full

set -eu

# BEGIN GENERATED: openwrt-overrides destiny login constants
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
FLAG="/etc/destiny-login-mode"
LOGIN_STEAM_NAME_TEMPLATE="pundef-pc steam via {primary} (destiny login)"
LOGIN_FULL_NAME_TEMPLATE="pundef-pc destiny login full via {primary}"
PC_ETH="192.168.1.133"
PC_WIFI="192.168.1.208"
# END GENERATED: openwrt-overrides destiny login constants

FULL=false
case "${1:-}" in
  --full|full) FULL=true ;;
esac
PRIMARY="${PRIMARY:-}"
if [ -z "${PRIMARY}" ]; then
  PRIMARY="$(uci -q get podkop.main.interface 2>/dev/null || true)"
fi
case "${PRIMARY}" in
  awg1|awg2) ;;
  *) PRIMARY=awg2 ;;
esac

PC_ETH="${PUNDEF_PC_ETH:-${PC_ETH}}"
PC_WIFI="${PUNDEF_PC_WIFI:-${PC_WIFI}}"

find_policy_idx() {
  name="$1"
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    existing="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    if [ "${existing}" = "${name}" ]; then
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

find_steam_policy_idx() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    case "${name}" in
      "pundef-pc steam via wan"|"pundef-pc steam via awg1"|"pundef-pc steam via awg2"|"pundef-pc steam via "*)
        echo "${i}"
        return 0
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}

echo "=== destiny login mode: Steam -> ${PRIMARY} ==="

if ! ifstatus "${PRIMARY}" | grep -q '"up": true'; then
  echo "ERROR: ${PRIMARY} is down" >&2
  exit 1
fi

if ! idx="$(find_steam_policy_idx 2>/dev/null)"; then
  echo "WARN: no steam policy — run apply-pundef-pc-routes.sh first" >&2
  exit 1
fi

uci set "pbr.@policy[${idx}].interface=${PRIMARY}"
steam_name="${LOGIN_STEAM_NAME_TEMPLATE//\{primary\}/${PRIMARY}}"
uci set "pbr.@policy[${idx}].name=${steam_name}"
uci set "pbr.@policy[${idx}].enabled=1"

# Drop duplicate steam-via-wan left by apply-pundef-pc-routes
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  if [ "${name}" = "pundef-pc steam via wan" ]; then
    echo "[destiny-login-mode] delete duplicate: ${name}" >&2
    uci delete "pbr.@policy[${i}]"
    i=0
    continue
  fi
  i=$((i + 1))
done

if [ "${FULL}" = true ]; then
  echo "=== enabling login FULL (0.0.0.0/0 -> ${PRIMARY}) ===" >&2
  catch_name="${LOGIN_FULL_NAME_TEMPLATE//\{primary\}/${PRIMARY}}"
  catch_idx=""
  if catch_idx="$(find_policy_idx "${catch_name}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    catch_idx="$(policy_count)"
    catch_idx=$((catch_idx - 1))
  fi
  uci set "pbr.@policy[${catch_idx}].name=${catch_name}"
  uci set "pbr.@policy[${catch_idx}].interface=${PRIMARY}"
  uci set "pbr.@policy[${catch_idx}].enabled=1"
  uci delete "pbr.@policy[${catch_idx}].src_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${catch_idx}].src_addr=${PC_ETH:-192.168.1.133}/32"
  uci add_list "pbr.@policy[${catch_idx}].src_addr=${PC_WIFI:-192.168.1.208}/32"
  uci delete "pbr.@policy[${catch_idx}].dest_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${catch_idx}].dest_addr=0.0.0.0/0"
  echo "[destiny-login-mode] catch-all ${catch_name} (idx ${catch_idx})" >&2
fi

uci commit pbr
/etc/init.d/pbr restart

if [ "${FULL}" = true ]; then
  echo "full" > "${FLAG}"
else
  echo "split" > "${FLAG}"
fi
echo "=== login mode ON (${FULL:+FULL }${FULL:-split}); wait ~15s ==="
echo "=== quit Steam -> restart Steam -> launch Destiny ==="
echo "=== after IN THE WORLD (tower/ship), NOT character select: apply_overrides.py --mode normal ==="


