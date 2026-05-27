#!/bin/sh
# zapret per-device / per-subnet ct bypass.
# Called from /opt/zapret/config: INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh
# Documented in docs/network/router-openwrt-x3000t.md ("Per-device bypass").
#
# Each rule is added only if not already present so re-runs are idempotent.

# phoneserver: postmarketOS on Redmi joyeuse (wlan0 MAC 02:00:89:de:af:ce, DHCP .116).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-116 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.116 return comment zapret-ct-bypass-116
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-116-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.116 return comment zapret-ct-bypass-116-pre

# pundef-pc (Win + WSL mirrored): Cloudflare CDN TLS handshake bypass. See zapret-bypass-pundef-pc-2026-05-27.
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-133 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.133 return comment zapret-ct-bypass-133
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-133-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.133 return comment zapret-ct-bypass-133-pre

# Whole srv subnet (Proxmox host + VMs): keep DPI off the server traffic.
# Effective only when traffic with saddr 192.168.50.x actually hits zapret postnat
# (e.g. asymmetric routing or routed scenarios).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-srv || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.50.0/24 return comment zapret-ct-bypass-srv
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-srv-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.50.0/24 return comment zapret-ct-bypass-srv-pre
