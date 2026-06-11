#!/bin/sh
# Remove Nexus Mods WAN pbr policy added by enable-nexus-wan.sh

set -eu

removed=0
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  case "${name}" in
    "pundef-pc nexus via wan")
      echo "[rollback-nexus-wan] delete: ${name}"
      uci delete "pbr.@policy[${i}]"
      removed=$((removed + 1))
      i=0
      continue
      ;;
  esac
  i=$((i + 1))
done

if [ "${removed}" -eq 0 ]; then
  echo "[rollback-nexus-wan] no matching policies found"
else
  uci commit pbr
  /etc/init.d/pbr restart
  echo "[rollback-nexus-wan] removed ${removed} policies"
fi
