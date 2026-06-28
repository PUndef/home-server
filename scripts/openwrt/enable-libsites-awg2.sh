#!/bin/sh
# Route Lib-family sites via primary AmneziaWG tunnel + WAN exceptions for DDG mirrors.
#
# DDoS-Guard mirrors (v3/v5.animelib.org) block datacenter/VPN egress (awg2 NL).
# OAuth callback on v5 → 403 geoblock; animelib.org (Cloudflare) works on VPN.
# Fix: v3/v5.animelib.org via WAN (residential RU IP); rest via awg*.
#
# Run on router: sh enable-libsites-awg2.sh
# From PC (lan/Wi‑Fi): py -3 scripts/openwrt/enable_libsites_awg2.py

set -eu

PRIMARY="$(uci -q get podkop.main.interface 2>/dev/null || true)"
case "${PRIMARY}" in
  awg1|awg2) ;;
  *) PRIMARY=awg2 ;;
esac

if ! ifstatus "${PRIMARY}" | grep -q '"up": true'; then
  echo "[enable-libsites-awg2] ERROR: ${PRIMARY} is down — aborting"
  exit 1
fi

POLICY_VPN="Mangalib via ${PRIMARY}"
POLICY_WAN="Lib DDG mirrors via wan"

# VPN: apex zones only — NOT *.animelib.org (v3/v5 blocked on VPN, see WAN policy).
LIB_VPN_DOMAINS="
  mangalib.me *.mangalib.me
  mangalib.org *.mangalib.org
  animelib.org
  hentailib.me *.hentailib.me
  ranobelib.me *.ranobelib.me
  ranobelib.org *.ranobelib.org
  lib.social *.lib.social
  imglib.org *.imglib.org
  slashlib.me *.slashlib.me
  shlib.life *.shlib.life
  yaoilib.me *.yaoilib.me
  yaoilib.net *.yaoilib.net
  yaoilib.org *.yaoilib.org
"

# WAN: DDG direct mirrors that geoblock awg2 exit IP (OAuth callback lands here).
LIB_WAN_DOMAINS="v3.animelib.org v5.animelib.org"

LIB_DNS_BYPASS="
  mangalib.me mangalib.org
  animelib.org
  hentailib.me
  ranobelib.me ranobelib.org
  lib.social
  imglib.org
  slashlib.me
  shlib.life
  yaoilib.me yaoilib.net yaoilib.org
"

LIB_BASE_DOMAINS="
  mangalib.me mangalib.org
  animelib.org
  hentailib.me
  ranobelib.me ranobelib.org
  lib.social
  imglib.org
  slashlib.me
  shlib.life
  yaoilib.me yaoilib.net yaoilib.org
"

add_dns_bypass() {
  domain="$1"
  entry="/${domain}/8.8.8.8"
  if uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep -Fq "=${entry}"; then
    return 0
  fi
  uci add_list "dhcp.@dnsmasq[0].server=${entry}"
  echo "[enable-libsites-awg2] dns bypass: ${entry}"
}

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

dest_addr_present() {
  idx="$1"
  domain="$2"
  existing_list="$(uci -q get "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true)"
  for existing in ${existing_list}; do
    if [ "${existing}" = "${domain}" ]; then
      return 0
    fi
  done
  return 1
}

remove_dest_addr() {
  idx="$1"
  domain="$2"
  i=0
  while uci -q get "pbr.@policy[${idx}].dest_addr[${i}]" >/dev/null 2>&1; do
    existing="$(uci -q get "pbr.@policy[${idx}].dest_addr[${i}]" 2>/dev/null || true)"
    if [ "${existing}" = "${domain}" ]; then
      uci delete "pbr.@policy[${idx}].dest_addr[${i}]"
      echo "[enable-libsites-awg2] removed dest_addr: ${domain}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

append_dest_addrs() {
  idx="$1"
  dest_list="$2"
  for d in ${dest_list}; do
    if dest_addr_present "${idx}" "${d}"; then
      echo "[enable-libsites-awg2] already in policy: ${d}"
      continue
    fi
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
    echo "[enable-libsites-awg2] added dest_addr: ${d}"
  done
}

upsert_wan_policy() {
  idx=""
  if idx="$(find_policy_idx "${POLICY_WAN}" 2>/dev/null)"; then
    :
  else
    uci add pbr policy >/dev/null
    idx=$(( $(policy_count) - 1 ))
  fi

  uci set "pbr.@policy[${idx}].name=${POLICY_WAN}"
  uci set "pbr.@policy[${idx}].interface=wan"
  uci set "pbr.@policy[${idx}].enabled=1"
  uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  for d in ${LIB_WAN_DOMAINS}; do
    uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
  done
  echo "[enable-libsites-awg2] policy ${POLICY_WAN} -> wan (idx ${idx})"
  echo "${idx}"
}

reorder_wan_before_vpn() {
  wan_idx="$1"
  vpn_idx=""
  if ! vpn_idx="$(find_policy_idx "${POLICY_VPN}" 2>/dev/null)"; then
    echo "[enable-libsites-awg2] WARN: ${POLICY_VPN} not found — skip reorder"
    return 0
  fi
  if [ "${wan_idx}" -gt "${vpn_idx}" ]; then
    uci reorder "pbr.@policy[${wan_idx}]=${vpn_idx}"
    echo "[enable-libsites-awg2] reordered WAN policy before VPN (was ${wan_idx}, now ${vpn_idx})"
  else
    echo "[enable-libsites-awg2] WAN policy already before VPN (${wan_idx} < ${vpn_idx})"
  fi
}

echo "=== enable Lib sites via ${PRIMARY} + WAN DDG mirrors ==="

for d in ${LIB_DNS_BYPASS}; do
  add_dns_bypass "${d}"
done

wan_idx="$(upsert_wan_policy)"

if ! vpn_idx="$(find_policy_idx "${POLICY_VPN}")"; then
  echo "[enable-libsites-awg2] WARN: ${POLICY_VPN} not found — creating policy"
  uci add pbr policy >/dev/null
  vpn_idx=0
  while uci -q get "pbr.@policy[${vpn_idx}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${vpn_idx}].name" 2>/dev/null || true)"
    if [ "${name}" = "${POLICY_VPN}" ]; then
      break
    fi
    vpn_idx=$((vpn_idx + 1))
  done
  uci set "pbr.@policy[${vpn_idx}].name=${POLICY_VPN}"
  uci set "pbr.@policy[${vpn_idx}].interface=${PRIMARY}"
  uci set "pbr.@policy[${vpn_idx}].enabled=1"
  for d in ${LIB_BASE_DOMAINS}; do
    uci add_list "pbr.@policy[${vpn_idx}].dest_addr=${d}"
  done
fi

# Drop wildcard that pulled v3/v5 into VPN (DDG geoblock on awg2).
remove_dest_addr "${vpn_idx}" "*.animelib.org" || true

append_dest_addrs "${vpn_idx}" "${LIB_VPN_DOMAINS}"

reorder_wan_before_vpn "${wan_idx}"

uci commit dhcp
uci commit pbr
/etc/init.d/dnsmasq restart
/etc/init.d/pbr restart

echo "=== done; wait ~15s then verify:"
echo "  nslookup v5.animelib.org 192.168.1.1"
echo "  curl -4 --interface wan -I https://v5.animelib.org/ru/front/auth/oauth/callback"
echo "  Prefer login URL: https://animelib.org/ru/front/auth (Cloudflare, works on VPN)"
