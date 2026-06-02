#!/bin/sh
# Allow LAN -> srv UDP for OwnCord TURN (coturn on 192.168.50.36).
# WAN relay also needs DNAT 3478/udp,tcp and 49152-65535/udp if used from internet.
set -e

DEST_IP="${OWNCORD_TURN_IP:-192.168.50.36}"

add_redirect() {
  name="$1"
  proto="$2"
  src_dport="$3"
  dest_port="$4"

  if uci show firewall 2>/dev/null | grep -q "name='${name}'"; then
    echo "[enable-owncord-turn] exists: ${name}"
    return 0
  fi

  uci add firewall redirect >/dev/null
  idx="$(uci show firewall | grep -c '=redirect')"
  idx=$((idx - 1))

  uci set "firewall.@redirect[${idx}].name=${name}"
  uci set "firewall.@redirect[${idx}].src=wan"
  uci set "firewall.@redirect[${idx}].dest=srv"
  uci set "firewall.@redirect[${idx}].proto=${proto}"
  uci set "firewall.@redirect[${idx}].src_dport=${src_dport}"
  uci set "firewall.@redirect[${idx}].dest_ip=${DEST_IP}"
  uci set "firewall.@redirect[${idx}].dest_port=${dest_port}"
  uci set "firewall.@redirect[${idx}].target=DNAT"
  echo "[enable-owncord-turn] added ${name}"
}

add_redirect owncord-turn-3478-tcp tcp 3478 3478
add_redirect owncord-turn-3478-udp udp 3478 3478
add_redirect owncord-turn-relay-udp udp 49152-65535 49152-65535

uci commit firewall
/etc/init.d/firewall reload
echo "[enable-owncord-turn] done (LAN uses ${DEST_IP}:3478 directly)"
