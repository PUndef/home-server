#!/bin/sh
# Route Optimizely Experimentation / Feature Experimentation via primary AmneziaWG tunnel.
# Global policy — all LAN clients. DNS bypass avoids podkop fake-IP on key endpoints.
#
# Run on router: sh enable-optimizely-awg2.sh
# From PC: py -3 scripts/openwrt/enable_optimizely_awg2.py

set -eu

PRIMARY="$(uci -q get podkop.main.interface 2>/dev/null || true)"
case "${PRIMARY}" in
  awg1|awg2) ;;
  *) PRIMARY=awg2 ;;
esac

if ! ifstatus "${PRIMARY}" | grep -q '"up": true'; then
  echo "[enable-optimizely-awg2] ERROR: ${PRIMARY} is down — aborting"
  exit 1
fi

POLICY_NAME="Optimizely via ${PRIMARY}"

# Support article + snippet/logx/datafile endpoints
OPTIMIZELY_DOMAINS="optimizely.com *.optimizely.com \
  app.optimizely.com *.app.optimizely.com \
  api.optimizely.com \
  cdn.optimizely.com cdn-pci.optimizely.com \
  cdn-prod.optimizely-static.com \
  logx.optimizely.com \
  p13n-results-api.optimizely.com"

DNS_BYPASS_DOMAINS="optimizely.com app.optimizely.com api.optimizely.com \
  cdn.optimizely.com cdn-pci.optimizely.com logx.optimizely.com \
  p13n-results-api.optimizely.com"

add_dns_bypass() {
  domain="$1"
  entry="/${domain}/8.8.8.8"
  if uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep -Fq "=${entry}"; then
    return 0
  fi
  uci add_list "dhcp.@dnsmasq[0].server=${entry}"
  echo "[enable-optimizely-awg2] dns bypass: ${entry}"
}

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

  echo "[enable-optimizely-awg2] policy ${policy_name} -> ${iface} (idx ${idx})"
}

echo "=== enable Optimizely via ${PRIMARY} ==="

for d in ${DNS_BYPASS_DOMAINS}; do
  add_dns_bypass "${d}"
done

upsert_policy "${POLICY_NAME}" "${PRIMARY}" "${OPTIMIZELY_DOMAINS}"

uci commit dhcp
uci commit pbr
/etc/init.d/dnsmasq restart
/etc/init.d/pbr restart

echo "=== done; wait ~15s then: nslookup cdn.optimizely.com 192.168.1.1 ==="
