#!/bin/sh
# Fill phoneserver «AI via awg2» nftset with Groq Cloudflare IPs.
# pbr 1.2.2 cannot populate this set from domains (no wildcards; phoneserver
# resolves api.groq.com via 1.1.1.1 → real CF IPs outside dnsmasq nftset).
#
# Safe to run after every pbr restart. Idempotent.
# Installed on router as /opt/seed-phoneserver-groq-ips.sh

set -eu

POLICY_NAME="phoneserver AI via awg2"
LOG_TAG="seed-phoneserver-groq"

find_phoneserver_nft_set() {
  nft list ruleset 2>/dev/null | awk '
    /set pbr_awg2_4_dst_ip/ { set = $2 }
    /phoneserver AI via awg2/ { print set; exit }
  '
}

seed_groq_ips() {
  set_name="$(find_phoneserver_nft_set)"
  if [ -z "${set_name}" ]; then
    return 0
  fi

  ips=""
  for domain in api.groq.com groq.com; do
    for ip in $(dig +short "${domain}" @1.1.1.1 A 2>/dev/null | sort -u); do
      case "${ip}" in
        *:*|"") continue ;;
      esac
      ips="${ips} ${ip}"
    done
  done

  ips="${ips} 104.18.18.125 104.18.19.125"

  added=0
  for ip in $(echo "${ips}" | tr ' ' '\n' | sort -u); do
    if nft add element inet fw4 "${set_name}" "{ ${ip} }" 2>/dev/null; then
      added=$((added + 1))
    fi
  done

  if [ "${added}" -gt 0 ]; then
    logger -t "${LOG_TAG}" "seeded ${added} IP(s) into ${set_name}"
    echo "[${LOG_TAG}] seeded ${added} IP(s) into ${set_name}"
  fi
}

seed_groq_ips
