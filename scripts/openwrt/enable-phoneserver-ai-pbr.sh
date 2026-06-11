#!/bin/sh
# Route phoneserver (HA + Groq API) egress via awg2.
# Phoneserver uses public DNS (1.1.1.1) → real Cloudflare IPs for api.groq.com,
# which miss the global AI dst set; src-based policy fixes Groq 403.
#
# Run on router: sh enable-phoneserver-ai-pbr.sh
# Or: PHONE_IP=192.168.1.227 bash ... from WSL via openwrt_exec

set -eu

PHONE_IP="${PHONE_IP:-192.168.1.227}"
POLICY_NAME="phoneserver AI via awg2"
IFACE="awg2"

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

last_policy_idx() {
  i=0
  last=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    last="${i}"
    i=$((i + 1))
  done
  echo "${last}"
}

if idx="$(find_policy_idx "${POLICY_NAME}")"; then
  uci set "pbr.@policy[${idx}].src_addr=${PHONE_IP}/32"
  uci set "pbr.@policy[${idx}].interface=${IFACE}"
  uci set "pbr.@policy[${idx}].enabled=1"
  echo "[phoneserver-ai-pbr] updated existing policy idx ${idx}"
else
  uci add pbr policy >/dev/null
  idx="$(last_policy_idx)"
  uci set "pbr.@policy[${idx}].name=${POLICY_NAME}"
  uci set "pbr.@policy[${idx}].interface=${IFACE}"
  uci set "pbr.@policy[${idx}].enabled=1"
  uci set "pbr.@policy[${idx}].src_addr=${PHONE_IP}/32"
  echo "[phoneserver-ai-pbr] created policy idx ${idx}"
fi

uci commit pbr
/etc/init.d/pbr restart

echo "[phoneserver-ai-pbr] ${PHONE_IP} -> ${IFACE}"
