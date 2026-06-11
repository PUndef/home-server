#!/bin/sh
# Test Groq HTTP from awg1 vs awg2 on router.
set -eu
for iface in awg2 awg1; do
  code=$(curl -sS -m 12 -o /dev/null -w '%{http_code}' --interface "${iface}" https://api.groq.com/openai/v1/models || echo ERR)
  echo "${iface}: ${code}"
done
