#!/bin/sh
# DEPRECATED — use apply_overrides.py --mode normal.
# Remove Steam-specific pbr policy (WAN or tunnel).
# Steam then follows "pundef-pc games via awg2" catch-all with Destiny.

set -eu

removed=0
i=0
while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
  name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
  case "${name}" in
    "pundef-pc steam via wan"|"pundef-pc steam via awg1"|"pundef-pc steam via awg2")
      echo "[rollback-steam-wan] delete: ${name}"
      uci delete "pbr.@policy[${i}]"
      removed=$((removed + 1))
      i=0
      continue
      ;;
  esac
  i=$((i + 1))
done

if [ "${removed}" -eq 0 ]; then
  echo "[rollback-steam-wan] no matching policies found"
else
  uci commit pbr
  /etc/init.d/pbr restart
  echo "[rollback-steam-wan] removed ${removed} policies"
fi
