#!/bin/sh
# Route phoneserver cloud AI (Groq + Yandex SpeechKit) egress via awg2.
# NOT a catch-all — local srv (Beszel hub 192.168.50.35) stays on lan→srv.
#
# Phoneserver uses public DNS (1.1.1.1) → real Cloudflare IPs for api.groq.com,
# which miss the global AI dst set; src+dest policy fixes Groq 403.
#
# Run on router: sh enable-phoneserver-ai-pbr.sh
# Or deploy via openwrt_exec / base64 pipe from PC.

set -eu

PHONE_IP="${PHONE_IP:-192.168.50.127}"
POLICY_NAME="phoneserver AI via awg2"
OLD_SRV_POLICY="phoneserver srv via lan"
IFACE="awg2"

AI_DOMAINS="api.groq.com groq.com *.groq.com \
  stt.api.cloud.yandex.net tts.api.cloud.yandex.net iam.api.cloud.yandex.net \
  api.cloud.yandex.net *.api.cloud.yandex.net"

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

if idx="$(find_policy_idx "${OLD_SRV_POLICY}" 2>/dev/null)"; then
  uci delete "pbr.@policy[${idx}]"
  echo "[phoneserver-ai-pbr] removed obsolete policy: ${OLD_SRV_POLICY}"
fi

if idx="$(find_policy_idx "${POLICY_NAME}")"; then
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
for d in ${AI_DOMAINS}; do
  uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
done

uci commit pbr
/etc/init.d/pbr restart

echo "[phoneserver-ai-pbr] ${PHONE_IP} -> ${IFACE} (domains only, idx ${idx})"
