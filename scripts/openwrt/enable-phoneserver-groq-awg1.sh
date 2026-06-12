#!/bin/sh
# Route phoneserver Groq egress via awg1 (if awg2 IP blocked by Cloudflare 1010).
set -eu

PHONE_IP="${PHONE_IP:-192.168.50.127}"
POLICY_NAME="phoneserver AI via awg2"
IFACE="awg1"

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

if idx="$(find_policy_idx "${POLICY_NAME}")"; then
  uci set "pbr.@policy[${idx}].interface=${IFACE}"
  uci set "pbr.@policy[${idx}].src_addr=${PHONE_IP}/32"
  uci set "pbr.@policy[${idx}].enabled=1"
  uci commit pbr
  /etc/init.d/pbr restart
  echo "[phoneserver-groq] ${PHONE_IP} -> ${IFACE} (policy idx ${idx})"
else
  echo "[phoneserver-groq] policy not found: ${POLICY_NAME}" >&2
  exit 1
fi
