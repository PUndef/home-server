#!/bin/sh
# Self-heal empty phoneserver Groq nftset after pbr restart / router reboot.
# pbr-workvpn-watchdog and 99-vpn-stack restart pbr without re-seeding Groq IPs.
#
# Cron on router: */5 * * * * /opt/pbr-phoneserver-groq-watchdog.sh

LOCK_FILE="/tmp/pbr-phoneserver-groq-watchdog.lock"
LOG_TAG="pbr-phoneserver-groq-watchdog"
SEED_SCRIPT="/opt/seed-phoneserver-groq-ips.sh"

[ -e "${LOCK_FILE}" ] && exit 0
touch "${LOCK_FILE}"
trap 'rm -f "${LOCK_FILE}"' EXIT

if ! uci show pbr 2>/dev/null | grep -q "phoneserver AI via awg2"; then
  exit 0
fi

if [ ! -f "${SEED_SCRIPT}" ]; then
  exit 0
fi

set_name="$(nft list ruleset 2>/dev/null | awk '
  /set pbr_awg2_4_dst_ip/ { set = $2 }
  /phoneserver AI via awg2/ { print set; exit }
')"

if [ -z "${set_name}" ]; then
  exit 0
fi

if nft list set inet fw4 "${set_name}" 2>/dev/null | grep -qE '8\.(6|47)\.|104\.18\.(18|19)\.'; then
  exit 0
fi

logger -t "${LOG_TAG}" "phoneserver Groq nftset empty or stale; re-seeding"
sh "${SEED_SCRIPT}"

exit 0
