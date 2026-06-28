#!/bin/sh
# zapret per-device / per-subnet ct bypass.
# Called from /opt/zapret/config: INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh
# Documented in docs/network/router-openwrt-x3000t.md ("Per-device bypass").
#
# Each rule is added only if not already present so re-runs are idempotent.

# phoneserver: postmarketOS on Redmi joyeuse (eth0 .227 via USB-Ethernet hub).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-227 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.227 return comment zapret-ct-bypass-227
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-227-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.227 return comment zapret-ct-bypass-227-pre

# pundef-pc Wi-Fi (.208): same zapret bypass class as lan eth .133
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-208 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.208 return comment zapret-ct-bypass-208
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-208-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.208 return comment zapret-ct-bypass-208-pre

# pundef-pc (Win + WSL mirrored): Cloudflare CDN TLS handshake bypass. See zapret-bypass-pundef-pc-2026-05-27.
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-133 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.133 return comment zapret-ct-bypass-133
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-133-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.133 return comment zapret-ct-bypass-133-pre

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
