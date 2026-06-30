#!/bin/sh
# DEPRECATED: LXC srv cannot SSH to OpenWrt. Use phoneserver systemd timer instead:
#   scripts/phoneserver/install-routing-status-collector.ps1
#
# Legacy stub kept for reference only.

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROUTING_PY="${ROUTING_STATUS_PY:-${SCRIPT_DIR}/routing_status.py}"
OUT_DIR="${ROUTING_STATUS_DIR:-/srv/static-sites/network-routing}"
STATUS_FILE="${OUT_DIR}/status.json"
HISTORY_FILE="${OUT_DIR}/history.jsonl"

mkdir -p "${OUT_DIR}"

if [ ! -f "${ROUTING_PY}" ]; then
  echo "routing_status.py not found: ${ROUTING_PY}" >&2
  exit 1
fi

PYTHON="${PYTHON:-python3}"
if command -v py >/dev/null 2>&1; then
  PYTHON="py -3"
fi

${PYTHON} "${ROUTING_PY}" --out "${STATUS_FILE}" || true

if [ -f "${STATUS_FILE}" ]; then
  ts="$(grep -m1 '"timestamp"' "${STATUS_FILE}" | sed 's/.*"timestamp": "\([^"]*\)".*/\1/')"
  overall="$(grep -m1 '"overall"' "${STATUS_FILE}" | sed 's/.*"overall": "\([^"]*\)".*/\1/')"
  fail_count="$(grep -m1 '"fail"' "${STATUS_FILE}" | sed 's/.*"fail": \([0-9]*\).*/\1/')"
  printf '{"timestamp":"%s","overall":"%s","fail":%s}\n' "${ts}" "${overall}" "${fail_count:-0}" >> "${HISTORY_FILE}"
  tail -n 480 "${HISTORY_FILE}" > "${HISTORY_FILE}.tmp" && mv "${HISTORY_FILE}.tmp" "${HISTORY_FILE}"
fi
