#!/bin/sh
# Enable corporate split-routing (workvpn) for a LAN client on OpenWrt X3000T.
# Run on the router as root, or: ssh root@192.168.1.1 'sh -s' < enable-workvpn-client.sh
#
# Required env (or defaults for Xiaomi 13T Pro test handset):
#   WORKVPN_CLIENT_NAME  - dhcp host name + pbr policy suffix
#   WORKVPN_CLIENT_MAC   - stable Wi-Fi MAC (disable random MAC on the phone)
#   WORKVPN_CLIENT_IP    - fixed LAN IP
#
# Example:
#   WORKVPN_CLIENT_NAME=xiaomi-13t-pro \
#   WORKVPN_CLIENT_MAC=36:63:0f:4d:4b:5c \
#   WORKVPN_CLIENT_IP=192.168.1.204 \
#   sh enable-workvpn-client.sh

set -eu

NAME="${WORKVPN_CLIENT_NAME:-xiaomi-13t-pro}"
MAC="$(echo "${WORKVPN_CLIENT_MAC:-36:63:0f:4d:4b:5c}" | tr 'A-Z' 'a-z')"
IP="${WORKVPN_CLIENT_IP:-192.168.1.204}"
POLICY_NAME="${NAME} kpb via workvpn"
DEST_ADDR="kpb.lt *.kpb.lt gitlab.kpb.lt 10.0.160.0/22 10.0.17.0/24"

# --- DHCP reservation ---
dhcp_idx=""
i=0
while uci -q get "dhcp.@host[${i}]" >/dev/null 2>&1; do
    existing_mac="$(uci -q get "dhcp.@host[${i}].mac" | tr 'A-Z' 'a-z')"
    existing_name="$(uci -q get "dhcp.@host[${i}].name" 2>/dev/null || true)"
    if [ "${existing_mac}" = "${MAC}" ] || [ "${existing_name}" = "${NAME}" ] || \
       [ "${existing_name}" = "Xiaomi-13T-Pro" ]; then
        dhcp_idx="${i}"
        break
    fi
    i=$((i + 1))
done
if [ -z "${dhcp_idx}" ]; then
    uci add dhcp host >/dev/null
    dhcp_idx="${i}"
fi
uci set "dhcp.@host[${dhcp_idx}].name=${NAME}"
uci set "dhcp.@host[${dhcp_idx}].mac=${MAC}"
uci set "dhcp.@host[${dhcp_idx}].ip=${IP}"
uci set "dhcp.@host[${dhcp_idx}].leasetime=infinite"
uci set "dhcp.@host[${dhcp_idx}].dhcp_option=6,192.168.1.1"

# --- pbr policy (same corp destinations as paul-mac) ---
pbr_idx=""
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    existing_name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    existing_src="$(uci -q get "pbr.@policy[${i}].src_addr" 2>/dev/null || true)"
    if [ "${existing_name}" = "${POLICY_NAME}" ] || [ "${existing_src}" = "${IP}" ]; then
        pbr_idx="${i}"
        break
    fi
    i=$((i + 1))
done
if [ -z "${pbr_idx}" ]; then
    uci add pbr policy >/dev/null
    pbr_idx="${i}"
fi
uci set "pbr.@policy[${pbr_idx}].name=${POLICY_NAME}"
uci set "pbr.@policy[${pbr_idx}].interface=workvpn"
uci set "pbr.@policy[${pbr_idx}].src_addr=${IP}"
uci delete "pbr.@policy[${pbr_idx}].dest_addr" 2>/dev/null || true
for d in ${DEST_ADDR}; do
    uci add_list "pbr.@policy[${pbr_idx}].dest_addr=${d}"
done
uci set "pbr.@policy[${pbr_idx}].enabled=1"

# --- Force DNS via router (needed when phone uses DoH/8.8.8.8) ---
add_dns_redirect() {
    proto="$1"
    rule_name="force-dns-${NAME}-${proto}"
    idx=""
    i=0
    while uci -q get "firewall.@redirect[${i}]" >/dev/null 2>&1; do
        existing_name="$(uci -q get "firewall.@redirect[${i}].name" 2>/dev/null || true)"
        if [ "${existing_name}" = "${rule_name}" ]; then
            idx="${i}"
            break
        fi
        i=$((i + 1))
done
    if [ -z "${idx}" ]; then
        uci add firewall redirect >/dev/null
        idx="${i}"
    fi
    uci set "firewall.@redirect[${idx}].name=${rule_name}"
    uci set "firewall.@redirect[${idx}].src=lan"
    uci set "firewall.@redirect[${idx}].proto=${proto}"
    uci set "firewall.@redirect[${idx}].src_ip=${IP}"
    uci set "firewall.@redirect[${idx}].src_dport=53"
    uci set "firewall.@redirect[${idx}].dest_ip=192.168.1.1"
    uci set "firewall.@redirect[${idx}].dest_port=53"
    uci set "firewall.@redirect[${idx}].target=DNAT"
    uci set "firewall.@redirect[${idx}].dest=lan"
}

add_dns_redirect udp
add_dns_redirect tcp

# --- Block DNS-over-TLS (Android "Private DNS") so client falls back to :53 hijack ---
add_block_dot() {
    proto="$1"
    rule_name="block-dot-${NAME}-${proto}"
    idx=""
    i=0
    while uci -q get "firewall.@rule[${i}]" >/dev/null 2>&1; do
        existing_name="$(uci -q get "firewall.@rule[${i}].name" 2>/dev/null || true)"
        if [ "${existing_name}" = "${rule_name}" ]; then
            idx="${i}"
            break
        fi
        i=$((i + 1))
    done
    if [ -z "${idx}" ]; then
        uci add firewall rule >/dev/null
        idx="${i}"
    fi
    uci set "firewall.@rule[${idx}].name=${rule_name}"
    uci set "firewall.@rule[${idx}].src=lan"
    uci set "firewall.@rule[${idx}].src_ip=${IP}"
    uci set "firewall.@rule[${idx}].dest_port=853"
    uci set "firewall.@rule[${idx}].proto=${proto}"
    uci set "firewall.@rule[${idx}].target=REJECT"
}

add_block_dot tcp
add_block_dot udp

uci commit dhcp
uci commit pbr
uci commit firewall
/etc/init.d/dnsmasq restart
/etc/init.d/pbr restart
/etc/init.d/firewall reload

echo "[enable-workvpn-client] ${NAME} ${MAC} -> ${IP}"
echo "[enable-workvpn-client] pbr policy: ${POLICY_NAME}"
echo "[enable-workvpn-client] On phone: Wi-Fi -> Private DNS off; renew DHCP if IP changed."
