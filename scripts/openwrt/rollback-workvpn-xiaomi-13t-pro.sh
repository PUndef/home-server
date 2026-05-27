#!/bin/sh
# Roll back workvpn setup for Xiaomi 13T Pro on OpenWrt X3000T.
# Restores corp routing without xiaomi-13t-pro. Does NOT touch paul-mac, pundef-pc, or workvpn tunnel.
#
# Run on router:
#   ssh root@192.168.1.1 'sh -s' < rollback-workvpn-xiaomi-13t-pro.sh
#
# Or paste into LuCI: System -> Terminal (as root).

set -eu

PHONE_IP="${WORKVPN_CLIENT_IP:-192.168.1.204}"
PHONE_NAME="${WORKVPN_CLIENT_NAME:-xiaomi-13t-pro}"
PAUL_IP="192.168.1.198"

echo "[rollback] Removing workvpn rules for ${PHONE_IP}..."

# --- pbr: drop phone from paul-mac policy; remove dedicated xiaomi policy ---
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    pname="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    if [ "${pname}" = "paul-mac kpb via workvpn" ]; then
        uci delete "pbr.@policy[${i}].src_addr" 2>/dev/null || true
        uci add_list "pbr.@policy[${i}].src_addr=${PAUL_IP}"
    elif echo "${pname}" | grep -qiE 'xiaomi|13t'; then
        uci delete "pbr.@policy[${i}]"
        i=$((i - 1))
    fi
    i=$((i + 1))
done

# --- firewall: remove phone-specific DNS redirect / DoT block ---
i=0
while uci -q get "firewall.@redirect[${i}]" >/dev/null 2>&1; do
    rname="$(uci -q get "firewall.@redirect[${i}].name" 2>/dev/null || true)"
    rip="$(uci -q get "firewall.@redirect[${i}].src_ip" 2>/dev/null || true)"
    if [ "${rip}" = "${PHONE_IP}" ] || echo "${rname}" | grep -qiE 'xiaomi|13t'; then
        uci delete "firewall.@redirect[${i}]"
        i=$((i - 1))
    fi
    i=$((i + 1))
done

i=0
while uci -q get "firewall.@rule[${i}]" >/dev/null 2>&1; do
    rname="$(uci -q get "firewall.@rule[${i}].name" 2>/dev/null || true)"
    rip="$(uci -q get "firewall.@rule[${i}].src_ip" 2>/dev/null || true)"
    if [ "${rip}" = "${PHONE_IP}" ] || echo "${rname}" | grep -qiE 'xiaomi|13t|doh'; then
        uci delete "firewall.@rule[${i}]"
        i=$((i - 1))
    fi
    i=$((i + 1))
done

# --- dhcp: keep reservation but drop forced DNS option ---
i=0
while uci -q get "dhcp.@host[${i}]" >/dev/null 2>&1; do
    hname="$(uci -q get "dhcp.@host[${i}].name" 2>/dev/null || true)"
    hip="$(uci -q get "dhcp.@host[${i}].ip" 2>/dev/null || true)"
    if [ "${hip}" = "${PHONE_IP}" ] || [ "${hname}" = "${PHONE_NAME}" ] || \
       [ "${hname}" = "Xiaomi-13T-Pro" ]; then
        uci delete "dhcp.@host[${i}].dhcp_option" 2>/dev/null || true
    fi
    i=$((i + 1))
done

uci commit pbr
uci commit firewall
uci commit dhcp
/etc/init.d/pbr restart
/etc/init.d/firewall reload
/etc/init.d/dnsmasq restart

echo "[rollback] Done. paul-mac only: src ${PAUL_IP}"
echo "[rollback] Check: ifstatus workvpn; ping -c1 8.8.8.8"
