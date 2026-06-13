#!/bin/sh
# Toggle Steam egress for pundef-pc between WAN (fast downloads) and primary tunnel.
#
#   awg2  — remove Steam exception; Steam + Destiny -> games catch-all (awg2)
#   wan   — Steam CDN/API -> WAN; Destiny still -> awg2
#   status — show current mode
#
# On router:
#   sh switch-steam-route.sh awg2
#   sh switch-steam-route.sh wan
#
# From PC:
#   py -3 scripts/openwrt/switch_steam_route.py awg2
#   py -3 scripts/openwrt/switch_steam_route.py wan

set -eu

MODE="${1:-}"
SCRIPT_DIR=""
case "$0" in
  */*)
    SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
    ;;
esac

steam_policy_name() {
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    case "${name}" in
      "pundef-pc steam via wan"|"pundef-pc steam via awg1"|"pundef-pc steam via awg2")
        echo "${name}"
        return 0
        ;;
    esac
    i=$((i + 1))
  done
  return 1
}

print_status() {
  primary="$(uci -q get podkop.main.interface 2>/dev/null || echo awg2)"
  i=0
  while uci -q get "pbr.@policy[${i}]" >/dev/null 2>&1; do
    name="$(uci -q get "pbr.@policy[${i}].name" 2>/dev/null || true)"
    case "${name}" in
      "pundef-pc steam via wan"|"pundef-pc steam via awg1"|"pundef-pc steam via awg2")
        iface="$(uci -q get "pbr.@policy[${i}].interface" 2>/dev/null || echo wan)"
        echo "mode=wan (policy: ${name} -> ${iface})"
        echo "Destiny / other games -> ${primary} (games catch-all)"
        return 0
        ;;
    esac
    i=$((i + 1))
  done
  echo "mode=awg2 (no Steam exception; Steam + Destiny -> ${primary} via games catch-all)"
}

run_peer() {
  peer="$1"
  if [ -n "${SCRIPT_DIR}" ] && [ -f "${SCRIPT_DIR}/${peer}" ]; then
    sh "${SCRIPT_DIR}/${peer}"
    return
  fi
  echo "ERROR: run from scripts/openwrt on router, or use: py -3 scripts/openwrt/switch_steam_route.py ${MODE}" >&2
  exit 1
}

case "${MODE}" in
  awg2|tunnel|vpn)
    echo "=== switch Steam route -> awg2 (with Destiny) ==="
    run_peer rollback-steam-wan.sh
    echo "=== done; wait ~15s, then restart Steam client ==="
    ;;
  wan|speed|direct)
    echo "=== switch Steam route -> WAN (fast downloads) ==="
    run_peer enable-steam-wan.sh
    ;;
  status)
    print_status
    ;;
  "")
    echo "Usage: $0 awg2|wan|status" >&2
    exit 1
    ;;
  *)
    echo "Unknown mode: ${MODE}" >&2
    echo "Usage: $0 awg2|wan|status" >&2
    exit 1
    ;;
esac
