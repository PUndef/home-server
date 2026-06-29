#!/bin/sh
# Canonical routing for pundef-pc (.133 eth / .208 wlan). NO catch-all 0.0.0.0/0.
#
# Idempotent — safe on boot, hotplug (99-vpn-stack), and cron watchdog.
#
# Usage:
#   sh apply-pundef-pc-routes.sh           # apply
#   sh apply-pundef-pc-routes.sh --check-only  # exit 1 if drift detected
#
# From PC:
#   py -3 scripts/openwrt/apply_overrides.py --mode normal

set -eu

# BEGIN GENERATED: openwrt-overrides apply constants
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
DESTINY_LOGIN_FLAG="/etc/destiny-login-mode"
# END GENERATED: openwrt-overrides apply constants

CHECK_ONLY=false
[ "${1:-}" = "--check-only" ] && CHECK_ONLY=true

if [ -f "${DESTINY_LOGIN_FLAG}" ] && [ "${CHECK_ONLY}" = false ]; then
  echo "[apply-pundef-pc-routes] destiny login mode active — skip (run apply_overrides.py --mode normal)"
  exit 0
fi

PC_ETH="${PUNDEF_PC_ETH:-192.168.1.133}"
PC_WIFI="${PUNDEF_PC_WIFI:-192.168.1.208}"
# Mercusys hub → X3000T lan2 (srv); real DNS 8.8.8.8 — catch-all via awg2 here is safe (no podkop fake-IP).
PC_SRV="${PUNDEF_PC_SRV:-192.168.50.133}"

PRIMARY="$(uci -q get podkop.main.interface 2>/dev/null || true)"
case "${PRIMARY}" in
  awg1|awg2) ;;
  *) PRIMARY=awg2 ;;
esac

# --- helpers ---

policy_count() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    i=$((i + 1))
  done
  echo "${i}"
}

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

delete_games_catchall() {
  removed=0
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    dest="$(uci -q get "pbr.@policy[${i}].dest_addr" 2>/dev/null || true)"
    case "${name}" in
      "pundef-pc games via "*|"pundef-pc destiny login full via "*)
        echo "[apply-pundef-pc-routes] delete policy: ${name}"
        uci delete "pbr.@policy[${i}]"
        removed=$((removed + 1))
        i=0
        continue
        ;;
      "pundef-pc srv default via "*)
        i=$((i + 1))
        continue
        ;;
    esac
    if echo "${dest}" | grep -q '0.0.0.0/0'; then
      src="$(uci -q get "pbr.@policy[${i}].src_addr" 2>/dev/null || true)"
      if echo "${src}" | grep -qE '192\.168\.1\.(133|208)'; then
        echo "[apply-pundef-pc-routes] delete 0.0.0.0/0 policy: ${name}"
        uci delete "pbr.@policy[${i}]"
        removed=$((removed + 1))
        i=0
        continue
      fi
    fi
    i=$((i + 1))
  done
  echo "${removed}"
}

delete_untitled_policies() {
  removed=0
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    dest_count="$(uci -q get "pbr.@policy[${i}].dest_addr" 2>/dev/null | wc -w)"
    src_count="$(uci -q get "pbr.@policy[${i}].src_addr" 2>/dev/null | wc -w)"
    if [ "${name}" = "Untitled" ] || { [ "${dest_count}" -eq 0 ] && [ "${src_count}" -eq 0 ]; }; then
      echo "[apply-pundef-pc-routes] delete broken policy: ${name:-<empty>}"
      uci delete "pbr.@policy[${i}]"
      removed=$((removed + 1))
      i=0
      continue
    fi
    i=$((i + 1))
  done
  echo "${removed}"
}

delete_destiny_login_policies() {
  removed=0
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    case "${name}" in
      *"(destiny login)"*)
        echo "[apply-pundef-pc-routes] delete login policy: ${name}" >&2
        uci delete "pbr.@policy[${i}]"
        removed=$((removed + 1))
        i=0
        continue
        ;;
    esac
    i=$((i + 1))
  done
  echo "${removed}"
}

add_dns_bypass() {
  domain="$1"
  entry="/${domain}/8.8.8.8"
  if uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep -Fq "=${entry}"; then
    return 0
  fi
  uci add_list "dhcp.@dnsmasq[0].server=${entry}"
  echo "[apply-pundef-pc-routes] dns bypass: ${entry}"
}

upsert_srv_default_policy() {
  policy_name="$1"
  iface="$2"

  idx=""
  if idx="$(find_policy_idx "${policy_name}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    idx="$(policy_count)"
    idx=$((idx - 1))
  fi

  uci set "pbr.@policy[${idx}].name=${policy_name}"
  uci set "pbr.@policy[${idx}].interface=${iface}"
  uci set "pbr.@policy[${idx}].enabled=1"

  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_SRV}/32"

  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${idx}].dest_addr=0.0.0.0/0"

  echo "[apply-pundef-pc-routes] srv-only policy ${policy_name} -> ${iface} (idx ${idx})" >&2
  echo "${idx}"
}

upsert_pc_policy() {
  policy_name="$1"
  iface="$2"
  dest_list="$3"

  idx=""
  if idx="$(find_policy_idx "${policy_name}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    idx="$(policy_count)"
    idx=$((idx - 1))
  fi

  uci set "pbr.@policy[${idx}].name=${policy_name}"
  uci set "pbr.@policy[${idx}].interface=${iface}"
  uci set "pbr.@policy[${idx}].enabled=1"

  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_ETH}/32"
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_WIFI}/32"
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_SRV}/32"

  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  for d in ${dest_list}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done

  echo "[apply-pundef-pc-routes] policy ${policy_name} -> ${iface} (idx ${idx})" >&2
  echo "${idx}"
}

upsert_lan_pc_policy() {
  policy_name="$1"
  iface="$2"
  dest_list="$3"

  idx=""
  if idx="$(find_policy_idx "${policy_name}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    idx="$(policy_count)"
    idx=$((idx - 1))
  fi

  uci set "pbr.@policy[${idx}].name=${policy_name}"
  uci set "pbr.@policy[${idx}].interface=${iface}"
  uci set "pbr.@policy[${idx}].enabled=1"

  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_ETH}/32"
  uci add_list "pbr.@policy[${idx}].src_addr=${PC_WIFI}/32"

  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  for d in ${dest_list}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done

  echo "[apply-pundef-pc-routes] lan policy ${policy_name} -> ${iface} (idx ${idx})" >&2
  echo "${idx}"
}

upsert_global_policy() {
  policy_name="$1"
  iface="$2"
  dest_list="$3"

  idx=""
  if idx="$(find_policy_idx "${policy_name}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    idx="$(policy_count)"
    idx=$((idx - 1))
  fi

  uci set "pbr.@policy[${idx}].name=${policy_name}"
  uci set "pbr.@policy[${idx}].interface=${iface}"
  uci set "pbr.@policy[${idx}].enabled=1"
  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true

  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  for d in ${dest_list}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done

  echo "[apply-pundef-pc-routes] global policy ${policy_name} -> ${iface} (idx ${idx})" >&2
  echo "${idx}"
}

reorder_policy_before() {
  policy_idx="$1"
  before_idx="$2"
  if [ "${policy_idx}" -gt "${before_idx}" ]; then
    uci reorder "pbr.@policy[${policy_idx}]=${before_idx}"
    echo "[apply-pundef-pc-routes] reordered idx ${policy_idx} -> ${before_idx}"
  fi
}

find_first_games_catchall_idx() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    dest="$(uci -q get "pbr.@policy[${i}].dest_addr" 2>/dev/null || true)"
    case "${name}" in
      pundef-pc\ games\ via\ *|pundef-pc\ destiny\ login\ full\ via\ *)
        echo "${i}"
        return 0
        ;;
      pundef-pc\ srv\ default\ via\ *)
        i=$((i + 1))
        continue
        ;;
    esac
    if echo "${dest}" | grep -q '0.0.0.0/0'; then
      src="$(uci -q get "pbr.@policy[${i}].src_addr" 2>/dev/null || true)"
      if echo "${src}" | grep -qE '192\.168\.1\.(133|208)'; then
        echo "${i}"
        return 0
      fi
    fi
    i=$((i + 1))
  done
  return 1
}

check_state() {
  drift=0

  if catch_idx="$(find_first_games_catchall_idx 2>/dev/null)"; then
    echo "[check] FAIL: catch-all still at pbr.@policy[${catch_idx}]"
    drift=1
  fi

  for want in \
    "pundef-pc steam via wan" \
    "pundef-pc nexus via wan" \
    "pundef-pc ru-local via wan" \
    "pundef-pc lib ddg via wan" \
    "pundef-pc discord via ${PRIMARY}" \
    "pundef-pc destiny via ${PRIMARY}" \
    "pundef-pc srv default via ${PRIMARY}" \
    "Warframe via ${PRIMARY}"
  do
    if ! find_policy_idx "${want}" >/dev/null 2>&1; then
      echo "[check] FAIL: missing policy ${want}"
      drift=1
    fi
  done

  for d in discord.com discord.gg bungie.net steamserver.net deadorbit.net gravityshavings.net; do
    if ! uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep -Fq "/${d}/8.8.8.8"; then
      echo "[check] FAIL: missing dns bypass /${d}/8.8.8.8"
      drift=1
    fi
  done

  return "${drift}"
}

# --- domain lists (generated from config/openwrt/overrides.json) ---

# BEGIN GENERATED: openwrt-overrides apply lists
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
STEAM_DOMAINS="steampowered.com \
  *.steampowered.com \
  steamcommunity.com \
  *.steamcommunity.com \
  steamcontent.com \
  *.steamcontent.com \
  steamstatic.com \
  *.steamstatic.com \
  valvesoftware.com \
  *.valvesoftware.com \
  steamcdn-a.akamaihd.net"

NEXUS_DOMAINS="nexusmods.com \
  *.nexusmods.com"

RU_LOCAL_DOMAINS="2gis.ru \
  *.2gis.ru \
  dublgis.ru \
  *.dublgis.ru"

LIB_DDG_DOMAINS="v3.animelib.org \
  v5.animelib.org"

WARFRAME_DOMAINS="warframe.com \
  *.warframe.com \
  api.warframe.com \
  content.warframe.com \
  soulframe.com \
  *.soulframe.com \
  digitalextremes.com \
  *.digitalextremes.com"

DISCORD_DNS="discord.com \
  discord.gg \
  discordapp.com \
  discordapp.net \
  discord.media \
  discordcdn.com \
  discordstatus.com"

DISCORD_DOMAINS="discord.com \
  *.discord.com \
  discord.gg \
  *.discord.gg \
  discordapp.com \
  *.discordapp.com \
  discordapp.net \
  *.discordapp.net \
  discord.media \
  *.discord.media \
  discordcdn.com \
  *.discordcdn.com \
  discordstatus.com \
  *.discordstatus.com \
  gateway.discord.gg"

# Destiny login / TAPIR bypass (CIS geo-block at auth only):
# https://github.com/Flowseal/zapret-discord-youtube/discussions/6033
DESTINY_DOMAINS="bungie.net \
  *.bungie.net \
  steamserver.net \
  *.steamserver.net \
  deadorbit.net \
  *.deadorbit.net \
  gravityshavings.net \
  *.gravityshavings.net"
# END GENERATED: openwrt-overrides apply lists

# --- main ---

if [ "${CHECK_ONLY}" = true ]; then
  if check_state; then
    echo "[check] OK: pundef-pc routes match canonical state"
    exit 0
  fi
  exit 1
fi

echo "=== apply pundef-pc routes (primary=${PRIMARY}, lan NO catch-all, srv default via ${PRIMARY}) ==="

delete_games_catchall >/dev/null || true
delete_untitled_policies >/dev/null || true
delete_destiny_login_policies >/dev/null || true

for d in ${DISCORD_DNS}; do
  add_dns_bypass "${d}"
done
for d in bungie.net steamserver.net deadorbit.net gravityshavings.net; do
  add_dns_bypass "${d}"
done
for d in 2gis.ru dublgis.ru; do
  add_dns_bypass "${d}"
done
for d in animelib.org; do
  add_dns_bypass "${d}"
done

steam_idx="$(upsert_pc_policy "pundef-pc steam via wan" "wan" "${STEAM_DOMAINS}")"
nexus_idx="$(upsert_pc_policy "pundef-pc nexus via wan" "wan" "${NEXUS_DOMAINS}")"
ru_local_idx="$(upsert_pc_policy "pundef-pc ru-local via wan" "wan" "${RU_LOCAL_DOMAINS}")"
lib_ddg_idx="$(upsert_pc_policy "pundef-pc lib ddg via wan" "wan" "${LIB_DDG_DOMAINS}")"
discord_idx="$(upsert_lan_pc_policy "pundef-pc discord via ${PRIMARY}" "${PRIMARY}" "${DISCORD_DOMAINS}")"
destiny_idx="$(upsert_pc_policy "pundef-pc destiny via ${PRIMARY}" "${PRIMARY}" "${DESTINY_DOMAINS}")"
srv_default_idx="$(upsert_srv_default_policy "pundef-pc srv default via ${PRIMARY}" "${PRIMARY}")"
warframe_idx="$(upsert_global_policy "Warframe via ${PRIMARY}" "${PRIMARY}" "${WARFRAME_DOMAINS}")"

# BEGIN GENERATED: openwrt-overrides policy reorder
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
# Policy order: steam -> nexus -> ru_local -> lib_ddg -> discord -> destiny_auth -> srv_default (warframe global — not reordered here)
# If steam policy landed late in uci, pull it ahead of nexus.
if [ "${steam_idx}" -gt "${nexus_idx}" ]; then
  reorder_policy_before "${steam_idx}" "${nexus_idx}"
fi
reorder_policy_before "${steam_idx}" "${nexus_idx}"
if [ "${ru_local_idx}" -gt "${nexus_idx}" ]; then
  reorder_policy_before "${ru_local_idx}" "${nexus_idx}"
fi
if [ "${lib_ddg_idx}" -gt "${ru_local_idx}" ]; then
  reorder_policy_before "${lib_ddg_idx}" "${ru_local_idx}"
fi
if [ "${discord_idx}" -gt "${lib_ddg_idx}" ]; then
  reorder_policy_before "${discord_idx}" "${lib_ddg_idx}"
fi
if [ "${destiny_idx}" -gt "${discord_idx}" ]; then
  reorder_policy_before "${destiny_idx}" "${discord_idx}"
fi
if [ "${srv_default_idx}" -gt "${destiny_idx}" ]; then
  reorder_policy_before "${srv_default_idx}" "${destiny_idx}"
fi
# END GENERATED: openwrt-overrides policy reorder

uci commit dhcp
uci commit pbr
/etc/init.d/dnsmasq restart
/etc/init.d/pbr restart

echo "=== done; policies applied without catch-all ==="








