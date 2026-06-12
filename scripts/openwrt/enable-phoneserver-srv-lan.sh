#!/bin/sh
# Legacy: route phoneserver lan IP -> srv via LAN (if phoneserver returns to 192.168.1.x).
# Must sit BEFORE "phoneserver AI via awg2" so Beszel agent reaches hub at 192.168.50.35.
#
# Run on router: sh enable-phoneserver-srv-lan.sh
# Or: ssh root@192.168.1.1 'sh -s' < enable-phoneserver-srv-lan.sh

set -eu

POLICY_NAME="phoneserver srv via lan"
PHONE_IP="${PHONE_IP:-192.168.50.127}"
SRV_NET="${SRV_NET:-192.168.50.0/24}"
IFACE="lan"
AI_POLICY="phoneserver AI via awg2"

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
  uci set "pbr.@policy[${idx}].src_addr=${PHONE_IP}/32"
  uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
  uci add_list "pbr.@policy[${idx}].dest_addr=${SRV_NET}"

  echo "[phoneserver-srv-lan] policy ${POLICY_NAME} -> ${IFACE} (idx ${idx})" >&2
  echo "${idx}"
}

reorder_before_ai() {
  srv_idx="$1"
  ai_idx=""
  if ! ai_idx="$(find_policy_idx "${AI_POLICY}" 2>/dev/null)"; then
    echo "[phoneserver-srv-lan] WARN: ${AI_POLICY} not found — skip reorder" >&2
    return 0
  fi

  if [ "${srv_idx}" -gt "${ai_idx}" ]; then
    uci reorder "pbr.@policy[${srv_idx}]=${ai_idx}"
    echo "[phoneserver-srv-lan] reordered srv policy before AI (was ${srv_idx}, now ${ai_idx})" >&2
  else
    echo "[phoneserver-srv-lan] srv policy already before AI (${srv_idx} < ${ai_idx})" >&2
  fi
}

echo "=== phoneserver ${PHONE_IP} -> ${SRV_NET} via ${IFACE} ==="

srv_idx="$(upsert_policy)"
reorder_before_ai "${srv_idx}"

uci commit pbr
/etc/init.d/pbr restart

echo "=== done; from phoneserver: ping 192.168.50.35 && curl http://192.168.50.35/beszel/ ==="
