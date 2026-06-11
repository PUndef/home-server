#!/bin/sh
set -eu
echo "egress: $(wget -qO- https://ifconfig.me/ip)"
echo -n "no_auth: "
wget -q -S -O /dev/null https://api.groq.com/openai/v1/models 2>&1 | head -1
