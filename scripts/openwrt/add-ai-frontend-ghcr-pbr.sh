#!/bin/sh
# Route ai-frontend LXC traffic to GitHub/GHCR through awg1 tunnel (same
# pattern as existing "AI Tools via awg1" policy). Needed because srv->wan
# is blocked by RKN for github.com/ghcr.io but the awg1 tunnel works.
set -e

if uci show pbr | grep -q "name='ai-frontend-ghcr-awg1'"; then
    echo "policy already exists"
    exit 0
fi

uci add pbr policy
uci set pbr.@policy[-1].name='ai-frontend-ghcr-awg1'
uci set pbr.@policy[-1].interface='awg1'
uci set pbr.@policy[-1].src_addr='192.168.50.36'
uci -q delete pbr.@policy[-1].dest_addr
uci add_list pbr.@policy[-1].dest_addr='ghcr.io'
uci add_list pbr.@policy[-1].dest_addr='pkg-containers.githubusercontent.com'
uci add_list pbr.@policy[-1].dest_addr='github.com'
uci add_list pbr.@policy[-1].dest_addr='codeload.github.com'
uci add_list pbr.@policy[-1].dest_addr='objects.githubusercontent.com'
uci add_list pbr.@policy[-1].dest_addr='avatars.githubusercontent.com'
uci set pbr.@policy[-1].enabled='1'
uci commit pbr

/etc/init.d/pbr reload
echo "--- new policy ---"
uci show pbr | grep ai-frontend-ghcr-awg1
