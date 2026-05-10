#!/bin/sh
# zapret per-device / per-subnet ct bypass
# called from /opt/zapret/config: INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh
# documented in router-openwrt-x3000t.md ("Per-device bypass")

# Single device: Redmi-Note-9-Pro
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-147 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.147 return comment zapret-ct-bypass-147
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-147-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.147 return comment zapret-ct-bypass-147-pre

# Whole srv subnet (Proxmox host + VMs): keep DPI off the server traffic.
# Effective only after switch-over (when traffic with saddr 192.168.50.x actually hits zapret postnat).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-srv || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.50.0/24 return comment zapret-ct-bypass-srv
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-srv-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.50.0/24 return comment zapret-ct-bypass-srv-pre
