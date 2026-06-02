#!/bin/sh
# Switch primary AmneziaWG tunnel for podkop, pbr AI/Mangalib/ghcr, srv forwarding,
# and GitHub community-list routes. Run on OpenWrt (or via stdin from PC helper).
#
# Usage: sh -s awg1|awg2   (argument after sh -s is $0 for the script body)

set -e

PRIMARY="$1"
[ -n "$PRIMARY" ] || PRIMARY="${0##*/}"
case "$PRIMARY" in
  awg1|awg2) ;;
  *)
    echo "Usage: $0 awg1|awg2" >&2
    exit 1
    ;;
esac

echo "=== switch primary tunnel -> $PRIMARY ==="

uci set podkop.main.interface="$PRIMARY"
uci commit podkop

# pbr: AI Tools, Mangalib, ai-frontend-ghcr policies
for sid in $(uci show pbr 2>/dev/null | sed -n "s/^\(pbr\.@policy\[[0-9]*\]\)=policy$/\1/p"); do
  name=$(uci -q get "${sid}.name" || true)
  case "$name" in
    *"AI Tools"*|*"Mangalib"*|*"ai-frontend-ghcr"*)
      uci set "${sid}.interface=$PRIMARY"
      newname=$(printf '%s' "$name" | sed "s/via awg[12]/via $PRIMARY/" | sed "s/-awg[12]/-$PRIMARY/")
      uci set "${sid}.name=$newname"
      echo "pbr: $name -> $newname ($PRIMARY)"
      ;;
  esac
done
uci commit pbr

# firewall: srv -> primary tunnel (OwnCord LXC ghcr pulls)
for sid in $(uci show firewall 2>/dev/null | sed -n "s/^\(firewall\.@forwarding\[[0-9]*\]\)=forwarding$/\1/p"); do
  src=$(uci -q get "${sid}.src" || true)
  [ "$src" = "srv" ] || continue
  dest=$(uci -q get "${sid}.dest" || true)
  case "$dest" in awg1|awg2)
    uci set "${sid}.dest=$PRIMARY"
    uci set "${sid}.name=srv-$PRIMARY"
    echo "firewall: srv forwarding -> $PRIMARY"
    ;;
  esac
done
uci commit firewall

HOTPLUG=/etc/hotplug.d/iface/99-vpn-stack
if [ -f "$HOTPLUG" ]; then
  sed -i "s/dev awg[12]/dev $PRIMARY/g" "$HOTPLUG"
  echo "hotplug: github routes -> dev $PRIMARY"
fi

ip route replace 185.199.108.0/22 dev "$PRIMARY" 2>/dev/null || true
ip route replace 140.82.112.0/20 dev "$PRIMARY" 2>/dev/null || true

/etc/init.d/firewall reload 2>/dev/null || true
/etc/init.d/sing-box restart 2>/dev/null || true
sleep 5
/etc/init.d/podkop restart 2>/dev/null || true
sleep 5
/etc/init.d/zapret restart 2>/dev/null || true
/etc/init.d/pbr restart 2>/dev/null || true

echo "=== done: primary=$PRIMARY (wait ~30s before health-check) ==="
