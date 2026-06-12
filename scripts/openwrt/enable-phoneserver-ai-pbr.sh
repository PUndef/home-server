#!/bin/sh
# Route phoneserver cloud AI (Groq + Yandex SpeechKit) egress via awg2.
# NOT a catch-all — local srv (Beszel hub 192.168.50.35) stays on lan→srv.
#
# Phoneserver uses public DNS (1.1.1.1) → real Cloudflare IPs for api.groq.com,
# which miss dnsmasq nftset and the global AI dst set. We keep a src+dest policy
# and seed Groq IPs via 1.1.1.1 after each pbr restart (wildcards break pbr 1.2.2).
#
# Run on router: sh enable-phoneserver-ai-pbr.sh
# Or deploy via openwrt_exec / upload.py + sh /tmp/enable-phoneserver-ai-pbr.sh

set -eu

PHONE_SRV_IP="${PHONE_SRV_IP:-192.168.50.127}"
PHONE_LAN_IP="${PHONE_LAN_IP:-192.168.1.227}"
POLICY_NAME="phoneserver AI via awg2"
OLD_SRV_POLICY="phoneserver srv via lan"
IFACE="awg2"
OPT_SEED="/opt/seed-phoneserver-groq-ips.sh"
OPT_WATCH="/opt/pbr-phoneserver-groq-watchdog.sh"
CRON_MARKER="pbr-phoneserver-groq-watchdog"

# No wildcards — pbr 1.2.2 logs "Unknown entry" and leaves the nftset empty.
AI_DOMAINS="api.groq.com groq.com \
  stt.api.cloud.yandex.net tts.api.cloud.yandex.net iam.api.cloud.yandex.net \
  api.cloud.yandex.net"

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

install_router_hooks() {
  script_dir="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

  if [ -f "${script_dir}/seed-phoneserver-groq-ips.sh" ]; then
    cp "${script_dir}/seed-phoneserver-groq-ips.sh" "${OPT_SEED}"
    chmod 0755 "${OPT_SEED}"
    sed -i 's/\r$//' "${OPT_SEED}" 2>/dev/null || true
  elif [ -x "${OPT_SEED}" ]; then
    :
  else
    echo "[phoneserver-ai-pbr] WARN: ${OPT_SEED} missing — upload seed-phoneserver-groq-ips.sh" >&2
  fi

  if [ -f "${script_dir}/pbr-phoneserver-groq-watchdog.sh" ]; then
    cp "${script_dir}/pbr-phoneserver-groq-watchdog.sh" "${OPT_WATCH}"
    chmod 0755 "${OPT_WATCH}"
    sed -i 's/\r$//' "${OPT_WATCH}" 2>/dev/null || true
  elif [ -x "${OPT_WATCH}" ]; then
    :
  else
    echo "[phoneserver-ai-pbr] WARN: ${OPT_WATCH} missing — upload pbr-phoneserver-groq-watchdog.sh" >&2
  fi

  if [ -f /etc/crontabs/root ] && ! grep -qF "${CRON_MARKER}" /etc/crontabs/root; then
    echo "*/5 * * * * ${OPT_WATCH}" >> /etc/crontabs/root
    /etc/init.d/cron restart 2>/dev/null || true
    echo "[phoneserver-ai-pbr] cron: */5 ${OPT_WATCH}"
  fi
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
uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
uci add_list "pbr.@policy[${idx}].src_addr=${PHONE_SRV_IP}/32"
uci add_list "pbr.@policy[${idx}].src_addr=${PHONE_LAN_IP}/32"
uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
for d in ${AI_DOMAINS}; do
  uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
done

uci commit pbr
install_router_hooks
/etc/init.d/pbr restart
[ -f "${OPT_SEED}" ] && sh "${OPT_SEED}"

echo "[phoneserver-ai-pbr] ${PHONE_SRV_IP} + ${PHONE_LAN_IP} -> ${IFACE} (idx ${idx})"
