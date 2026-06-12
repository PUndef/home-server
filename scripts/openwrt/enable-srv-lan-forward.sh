#!/bin/sh
# Allow srv (192.168.50.x) -> lan (192.168.1.x) forwarding.
# Needed for Uptime Kuma on static-sites (.35) to ping/monitor LAN devices.
#
# Run on router: sh enable-srv-lan-forward.sh

set -eu

NAME="srv-lan"

find_idx() {
  i=0
  while uci -q get "firewall.@forwarding[${i}]" >/dev/null 2>&1; do
    n="$(uci -q get "firewall.@forwarding[${i}].name" 2>/dev/null || true)"
    if [ "${n}" = "${NAME}" ]; then
      echo "${i}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

if idx="$(find_idx 2>/dev/null)"; then
  echo "[srv-lan] forwarding already exists (idx ${idx})"
else
  uci add firewall forwarding >/dev/null
  idx="$(uci show firewall | grep '=forwarding' | wc -l)"
  idx=$((idx - 1))
  uci set "firewall.@forwarding[${idx}].name=${NAME}"
  uci set "firewall.@forwarding[${idx}].src=srv"
  uci set "firewall.@forwarding[${idx}].dest=lan"
  echo "[srv-lan] created forwarding idx ${idx}"
fi

uci commit firewall
/etc/init.d/firewall reload

echo "[srv-lan] done; from srv: ping 192.168.1.1 && ping 192.168.1.171"
