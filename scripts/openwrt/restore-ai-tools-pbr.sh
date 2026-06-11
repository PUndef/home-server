#!/bin/sh
# Restore AI Tools pbr policy if missing (accidentally overwritten by early enable-nexus-wan.sh).

set -eu

POLICY_NAME="AI Tools via awg2 (global)"
IFACE="awg2"

AI_DOMAINS="api2.cursor.sh api3.cursor.sh api4.cursor.sh repo42.cursor.sh \
  authenticate.cursor.sh authenticator.cursor.sh marketplace.cursorapi.com \
  cursor.com www.cursor.com cursor-cdn.com cursor.sh cursorapi.com \
  api.anthropic.com console.anthropic.com claude.ai anthropic.com \
  api.openai.com openai.com chatgpt.com api.groq.com \
  generativelanguage.googleapis.com googleapis.com \
  www.anthropic.com www.claude.ai claudeusercontent.com anthropicusercontent.com \
  cdn.anthropic.com support.anthropic.com"

find_policy_idx() {
  name="$1"
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    existing_name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    if [ "${existing_name}" = "${name}" ]; then
      echo "${i}"
      return 0
    fi
    i=$((i + 1))
  done
  return 1
}

last_policy_idx() {
  i=0
  last=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    last="${i}"
    i=$((i + 1))
  done
  echo "${last}"
}

if find_policy_idx "${POLICY_NAME}" >/dev/null 2>&1; then
  echo "[restore-ai-tools-pbr] already present"
  exit 0
fi

uci add pbr policy >/dev/null
idx="$(last_policy_idx)"

uci set "pbr.@policy[${idx}].name=${POLICY_NAME}"
uci set "pbr.@policy[${idx}].interface=${IFACE}"
uci set "pbr.@policy[${idx}].enabled=1"
uci delete "pbr.@policy[${idx}].src_addr" 2>/dev/null || true
uci delete "pbr.@policy[${idx}].dest_addr" 2>/dev/null || true
for d in ${AI_DOMAINS}; do
  uci add_list "pbr.@policy[${idx}].dest_addr=${d}"
done

# Global AI policy first in chain.
uci reorder "pbr.@policy[${idx}]=0"

uci commit pbr
/etc/init.d/pbr restart

echo "[restore-ai-tools-pbr] restored at idx ${idx}, moved to position 0"
