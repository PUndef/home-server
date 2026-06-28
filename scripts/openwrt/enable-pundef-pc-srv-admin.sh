#!/bin/sh
# Allow SSH + LuCI from pundef-pc Mercusys eth (192.168.50.133) to the router.
# Run ONCE from lan/Wi-Fi (192.168.1.x) — srv cannot reach router admin until this exists.
#
#   py -3 scripts/openwrt/openwrt_exec.py "sh -s" < scripts/openwrt/enable-pundef-pc-srv-admin.sh
# Or paste on router after SSH from Mac / lan cable.

set -eu

PC_SRV="${PUNDEF_PC_SRV:-192.168.50.133}"
RULE_NAME="Allow pundef-pc srv admin"

if uci show firewall 2>/dev/null | grep -Fq "name='${RULE_NAME}'"; then
  echo "[srv-admin] rule already present"
  exit 0
fi

uci add firewall rule >/dev/null
idx="$(uci show firewall 2>/dev/null | sed -n 's/^firewall\.@rule\[\([0-9]*\)\]=rule$/\1/p' | tail -1)"

uci set "firewall.@rule[${idx}].name=${RULE_NAME}"
uci set "firewall.@rule[${idx}].src=srv"
uci set "firewall.@rule[${idx}].src_ip=${PC_SRV}"
uci set "firewall.@rule[${idx}].dest_port=22 80 443"
uci set "firewall.@rule[${idx}].proto=tcp"
uci set "firewall.@rule[${idx}].target=ACCEPT"
uci set "firewall.@rule[${idx}].family=ipv4"

uci commit firewall
/etc/init.d/firewall reload

echo "[srv-admin] ${PC_SRV} -> router tcp/22,80,443 ACCEPT (zone srv)"
