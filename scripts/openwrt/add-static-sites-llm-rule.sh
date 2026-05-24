#!/bin/sh
# Allow static-sites LXC (srv:192.168.50.35) to proxy to phoneserver llama API
# (lan:192.168.1.116:8080) for /chat/llm/* on Caddy.
set -e

RULE_NAME='static-sites-to-phoneserver-llm'

if uci show firewall | grep -q "name='${RULE_NAME}'"; then
    echo "rule already exists"
    exit 0
fi

uci add firewall rule
uci set firewall.@rule[-1].name="${RULE_NAME}"
uci set firewall.@rule[-1].src='srv'
uci set firewall.@rule[-1].src_ip='192.168.50.35'
uci set firewall.@rule[-1].dest='lan'
uci set firewall.@rule[-1].dest_ip='192.168.1.116'
uci set firewall.@rule[-1].dest_port='8080'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall

/etc/init.d/firewall reload
echo "--- new rule ---"
uci show firewall | grep static-sites-to-phoneserver
