#!/bin/sh
# Remove ai-frontend -> phoneserver llm firewall rule.
set -e

RULE_NAME='ai-frontend-to-phoneserver-llm'
id=$(uci show firewall 2>/dev/null | sed -n "s/^\(firewall\.@rule\[[0-9]*\]\)\.name='${RULE_NAME}'/\1/p" | head -1)
if [ -z "$id" ]; then
    echo "rule not found"
    exit 0
fi
uci -q delete "$id"
uci commit firewall
/etc/init.d/firewall reload
echo "removed ${RULE_NAME}"
