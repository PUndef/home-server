#!/bin/sh
# zapret per-device / per-subnet ct bypass.
# Called from /opt/zapret/config: INIT_FW_POST_UP_HOOK=/opt/zapret/custom.bypass_devices.sh
# Documented in router-openwrt-x3000t.md ("Per-device bypass").
#
# Each rule is added only if not already present so re-runs are idempotent.

# Phone: Redmi-Note-9-Pro (real device MAC 18:87:40:44:cd:51, DHCP-pinned to .157).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-157 || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.1.157 return comment zapret-ct-bypass-157
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-157-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.1.157 return comment zapret-ct-bypass-157-pre

# Whole srv subnet (Proxmox host + VMs): keep DPI off the server traffic.
# Effective only when traffic with saddr 192.168.50.x actually hits zapret postnat
# (e.g. asymmetric routing or routed scenarios).
nft list chain inet zapret postnat 2>/dev/null | grep -q zapret-ct-bypass-srv || \
    nft insert rule inet zapret postnat ct original ip saddr 192.168.50.0/24 return comment zapret-ct-bypass-srv
nft list chain inet zapret prenat 2>/dev/null | grep -q zapret-ct-bypass-srv-pre || \
    nft insert rule inet zapret prenat ct reply ip daddr 192.168.50.0/24 return comment zapret-ct-bypass-srv-pre
