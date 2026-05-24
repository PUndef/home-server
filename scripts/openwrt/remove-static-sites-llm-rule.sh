#!/bin/sh
# Remove static-sites -> phoneserver llm firewall rule (chat teardown).
set -e

RULE_NAME='static-sites-to-phoneserver-llm'
id=$(uci show firewall 2>/dev/null | sed -n "s/^\(firewall\.@rule\[[0-9]*\]\)\.name='${RULE_NAME}'/\1/p" | head -1)
if [ -z "$id" ]; then
    echo "rule not found"
    exit 0
fi
uci -q delete "$id"
uci commit firewall
/etc/init.d/firewall reload
echo "removed ${RULE_NAME}"
