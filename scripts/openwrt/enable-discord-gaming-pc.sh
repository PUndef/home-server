#!/bin/sh
# Fix Discord on pundef-pc (.133 eth / .208 wlan).
#
# games catch-all (0.0.0.0/0 -> awg2) steals podkop fake-IP (198.18.0.0/15):
# Discord resolves to 198.18.x, pbr sends it into awg2 without sing-box tproxy -> dead.
#
# Same pattern as Spotify: resolve Discord via public DNS (real IPs), then
# games catch-all routes real Discord IPs through awg2 normally.
#
# Run on router: sh enable-discord-gaming-pc.sh
# From PC: py -3 scripts/openwrt/enable_discord_gaming_pc.py

set -eu

DISCORD_DOMAINS="discord.com discord.gg discordapp.com discordapp.net \
  discord.media discordcdn.com discordstatus.com"

add_dns_bypass() {
  domain="$1"
  entry="/${domain}/8.8.8.8"
  if uci show dhcp.@dnsmasq[0].server 2>/dev/null | grep -Fq "=${entry}"; then
    echo "[enable-discord-gaming-pc] dns bypass exists: ${entry}"
    return 0
  fi
  uci add_list "dhcp.@dnsmasq[0].server=${entry}"
  echo "[enable-discord-gaming-pc] dns bypass added: ${entry}"
}

echo "=== enable Discord DNS bypass (gaming PC / LAN) ==="

for d in ${DISCORD_DOMAINS}; do
  add_dns_bypass "${d}"
done

uci commit dhcp
/etc/init.d/dnsmasq restart
/etc/init.d/pbr restart

echo "=== done; wait ~15s, then: nslookup discord.com 192.168.1.1 (must NOT be 198.18.x) ==="
