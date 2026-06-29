#!/bin/sh
# zapret per-device / per-subnet ct bypass.
# Called from /opt/zapret/config: INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh
# Documented in docs/network/router-openwrt-x3000t.md ("Per-device bypass").
#
# Each rule is added only if not already present so re-runs are idempotent.

# Delete every rule carrying a given nft comment (used to migrate old all-proto
# bypass rules to TCP-only without a full zapret restart).
delete_nft_by_comment() {
  table="$1"
  chain="$2"
  comment="$3"
  while true; do
    handle=$(nft -a list chain "$table" "$chain" 2>/dev/null \
      | grep "comment \"$comment\"" | head -1 | awk '{print $NF}')
    [ -n "$handle" ] || break
    nft delete rule "$table" "$chain" handle "$handle" 2>/dev/null || break
  done
}

# phoneserver: postmarketOS on Redmi joyeuse (eth0 .227 via USB-Ethernet hub).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-227 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.227 return comment zapret-ct-bypass-227
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-227-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.227 return comment zapret-ct-bypass-227-pre

# pundef-pc eth .133 (Win + WSL mirrored): TCP bypass for Cloudflare CDN TLS handshake
# (Cursor Remote SSH / WSL nodesource), see incidents/zapret-bypass-pundef-pc-2026-05-27.md.
# NOTE: blanket TCP bypass also disables zapret SNI-desync for Discord on .133; if Discord
# is used on .133, narrow this to Cloudflare ranges (see docs/network/gaming-pc-routes.md).
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-133"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-133-pre"
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-133-tcp || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.133 meta l4proto tcp return comment zapret-ct-bypass-133-tcp
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-133-pre-tcp || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.133 meta l4proto tcp return comment zapret-ct-bypass-133-pre-tcp

# pundef-pc wlan .208: NO bypass for TCP/Discord-UDP. Discord (TCP gateway + UDP voice)
# needs zapret SNI/UDP desync to connect on this ISP; bypassing TCP blocks fresh Discord
# connections, bypassing voice UDP throttles voice. Remove any legacy .208 bypass rules.
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-208"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-208-pre"
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-208-tcp"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-208-pre-tcp"

# Destiny 2 servers must bypass nfqws, but Discord voice (same PC, same UDP port ranges)
# MUST keep zapret. Port-based split is impossible (they overlap), so we split by DESTINATION
# IP: bypass only Destiny's server ranges, leave everything else (incl. Discord) on zapret.
# Captured live during a working activity load (2026-06-30, see gaming-pc-routes.md):
#   155.133.0.0/16, 162.254.0.0/16 = Valve Steam Datagram Relay (Destiny relays, :27015-27055)
#   205.209.0.0/16                 = Bungie/Multiplay dedicated servers (:3074)
#   57.129.90.115/32               = Destiny activity server seen on :3079/:3080 (currant)
# Do NOT include 104.29.154.0/24 here: a clean Discord-only capture showed
# Discord voice on 104.29.154.185:19315, so bypassing it breaks Discord voice.
# zapret mangling these -> "centipede"/"currant"/"cabbage"/"hare"; raw WAN to them works.
# BEGIN GENERATED: openwrt-overrides zapret destiny nets
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
# Destiny activity servers must bypass nfqws; Discord voice must remain outside this bypass.
# Forbidden in Destiny bypass: 104.29.154.0/24
DESTINY_NETS="{ 57.129.90.115/32, 155.133.0.0/16, 162.254.0.0/16, 205.196.0.0/16, 205.209.0.0/16 }"
# END GENERATED: openwrt-overrides zapret destiny nets
# migrate any legacy port-based game rules first
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-133-destiny"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-133-destiny-pre"
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-208-destiny"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-208-destiny-pre"
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-133-games"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-133-games-pre"
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-208-games"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-208-games-pre"
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-133-destiny-ip"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-133-destiny-ip-pre"
delete_nft_by_comment inet zapret postnat "zapret-ct-bypass-208-destiny-ip"
delete_nft_by_comment inet zapret prenat "zapret-ct-bypass-208-destiny-ip-pre"
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-133-destiny-ip || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.133 ip daddr $DESTINY_NETS return comment zapret-ct-bypass-133-destiny-ip
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-133-destiny-ip-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.133 ip saddr $DESTINY_NETS return comment zapret-ct-bypass-133-destiny-ip-pre
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-208-destiny-ip || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.208 ip daddr $DESTINY_NETS return comment zapret-ct-bypass-208-destiny-ip
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-208-destiny-ip-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.208 ip saddr $DESTINY_NETS return comment zapret-ct-bypass-208-destiny-ip-pre

# Destiny instance / lost sector load: dynamic Steam relay IPs outside 155.133/162.254.
# BEGIN GENERATED: openwrt-overrides zapret steam sdr
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
STEAM_SDR_CLIENTS="192.168.1.133 192.168.1.208"
STEAM_SDR_UDP_DPORT="27000-27200"
STEAM_SDR_FORBIDDEN="104.29.154.0/24"
# END GENERATED: openwrt-overrides zapret steam sdr
for client_ip in ${STEAM_SDR_CLIENTS}; do
  client_suffix="${client_ip##*.}"
  nft list chain inet zapret postnat 2>/dev/null | grep -q "zapret-ct-bypass-${client_suffix}-steam-sdr" || \
      nft insert rule inet zapret postnat ct original ip saddr "${client_ip}" ip daddr != ${STEAM_SDR_FORBIDDEN} udp dport ${STEAM_SDR_UDP_DPORT} return comment "zapret-ct-bypass-${client_suffix}-steam-sdr"
  nft list chain inet zapret prenat 2>/dev/null | grep -q "zapret-ct-bypass-${client_suffix}-steam-sdr-pre" || \
      nft insert rule inet zapret prenat ct reply ip daddr "${client_ip}" ip saddr != ${STEAM_SDR_FORBIDDEN} udp sport ${STEAM_SDR_UDP_DPORT} return comment "zapret-ct-bypass-${client_suffix}-steam-sdr-pre"
done

# xiaomi-13t-pro: Android TLS/DPI bypass (same symptom class as pundef-pc).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-214 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.214 return comment zapret-ct-bypass-214
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-214-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.214 return comment zapret-ct-bypass-214-pre

# Whole srv subnet (Proxmox host + VMs): keep DPI off the server traffic.
# Effective only when traffic with saddr 192.168.50.x actually hits zapret postnat
# (e.g. asymmetric routing or routed scenarios).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-srv || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.50.0/24 return comment zapret-ct-bypass-srv
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-srv-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.50.0/24 return comment zapret-ct-bypass-srv-pre




