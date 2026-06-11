#!/bin/sh
# Remove Warframe / Soulframe pbr policies added by enable-warframe-awg2.sh

set -eu

removed=0
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  case "${name}" in
    Warframe\ via\ *|pundef-pc\ games\ via\ *)
      echo "[rollback-warframe-awg2] delete: ${name}"
      uci delete "pbr.@policy[${i}]"
      removed=$((removed + 1))
      i=0
      continue
      ;;
  esac
  i=$((i + 1))
done

if [ "${removed}" -eq 0 ]; then
  echo "[rollback-warframe-awg2] no matching policies found"
else
  uci commit pbr
  /etc/init.d/pbr restart
  echo "[rollback-warframe-awg2] removed ${removed} policies"
fi
