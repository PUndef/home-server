#!/bin/sh
# 1) Add dest_addr list to ai-frontend-ghcr-awg1 policy (didn't persist last time)
# 2) Add firewall forwarding srv -> awg1 (so marked packets can actually leave)
set -e

POLICY_NAME='ai-frontend-ghcr-awg1'

# Find the section name by policy name
SECT=$(uci show pbr | grep "name='${POLICY_NAME}'" | head -1 | cut -d. -f2 | cut -d= -f1)
echo "policy section: $SECT"

uci set pbr.${SECT}.dest_addr=''
uci add_list pbr.${SECT}.dest_addr='ghcr.io'
uci add_list pbr.${SECT}.dest_addr='pkg-containers.githubusercontent.com'
uci add_list pbr.${SECT}.dest_addr='github.com'
uci add_list pbr.${SECT}.dest_addr='codeload.github.com'
uci add_list pbr.${SECT}.dest_addr='objects.githubusercontent.com'
uci add_list pbr.${SECT}.dest_addr='avatars.githubusercontent.com'
uci add_list pbr.${SECT}.dest_addr='raw.githubusercontent.com'
uci add_list pbr.${SECT}.dest_addr='api.github.com'
uci commit pbr

# Add firewall forwarding srv -> awg1 if not already present
if uci show firewall | grep -E "forwarding.*src='srv'" | grep -q awg1; then
    echo "srv->awg1 forwarding already exists"
else
    uci add firewall forwarding
    uci set firewall.@forwarding[-1].name='srv-awg1'
    uci set firewall.@forwarding[-1].src='srv'
    uci set firewall.@forwarding[-1].dest='awg1'
    uci commit firewall
    /etc/init.d/firewall reload
    echo "added srv->awg1 forwarding"
fi

/etc/init.d/pbr reload
echo
echo "=== policy after fix ==="
uci show pbr.${SECT}
echo
echo "=== forwarding ==="
uci show firewall | grep forwarding | grep -E "srv|awg1"
