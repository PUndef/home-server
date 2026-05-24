#!/bin/sh
# Allow LXC 103 ai-frontend (srv:192.168.50.36) to reach the llama-server
# HTTP API on phoneserver (lan:192.168.1.116:8080). Temporary — when
# phoneserver moves to the srv segment over wired Ethernet, this rule
# can be deleted (uci -X delete firewall.<name>).
set -e

# Skip if rule already present
if uci show firewall | grep -q "name='ai-frontend-to-phoneserver-llm'"; then
    echo "rule already exists"
    exit 0
fi

uci add firewall rule
uci set firewall.@rule[-1].name='ai-frontend-to-phoneserver-llm'
uci set firewall.@rule[-1].src='srv'
uci set firewall.@rule[-1].src_ip='192.168.50.36'
uci set firewall.@rule[-1].dest='lan'
uci set firewall.@rule[-1].dest_ip='192.168.1.116'
uci set firewall.@rule[-1].dest_port='8080'
uci set firewall.@rule[-1].proto='tcp'
uci set firewall.@rule[-1].target='ACCEPT'
uci commit firewall

/etc/init.d/firewall reload
echo "--- new rule ---"
uci show firewall | grep ai-frontend-to-phoneserver
