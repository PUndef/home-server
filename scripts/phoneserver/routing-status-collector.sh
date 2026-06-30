#!/bin/sh
# Collect OpenWrt routing status (wlan -> router SSH) and publish to static-sites LXC (eth).
# Installed by install-routing-status-collector.sh on phoneserver.

set -eu

ENV_FILE="/etc/routing-status-collector.env"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1091
  . "${ENV_FILE}"
fi

: "${OPENWRT_HOST:=192.168.1.1}"
: "${OPENWRT_KEY:?OPENWRT_KEY required}"
: "${LXC_TARGET:=deploy@192.168.50.35}"
: "${LXC_KEY:?LXC_KEY required}"
: "${LXC_DIR:=/srv/static-sites/network-routing}"

INSTALL_ROOT="${INSTALL_ROOT:-/opt/home-server}"
ROUTING_PY="${INSTALL_ROOT}/scripts/openwrt/routing_status.py"
MANIFEST="${INSTALL_ROOT}/config/openwrt/overrides.json"
LOCAL_STATUS="/tmp/routing-status.json"
LOCAL_HISTORY="/tmp/routing-status-history-line.jsonl"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

if [ ! -f "${ROUTING_PY}" ]; then
  echo "missing ${ROUTING_PY}" >&2
  exit 1
fi

export OPENWRT_HOST OPENWRT_KEY
python3 "${ROUTING_PY}" --manifest "${MANIFEST}" --out "${LOCAL_STATUS}" || true

if [ ! -f "${LOCAL_STATUS}" ]; then
  echo "status snapshot not produced" >&2
  exit 1
fi

scp ${SSH_OPTS} -i "${LXC_KEY}" "${LOCAL_STATUS}" "${LXC_TARGET}:${LXC_DIR}/status.json"

ts="$(grep -m1 '"timestamp"' "${LOCAL_STATUS}" | sed 's/.*"timestamp": "\([^"]*\)".*/\1/')"
overall="$(grep -m1 '"overall"' "${LOCAL_STATUS}" | sed 's/.*"overall": "\([^"]*\)".*/\1/')"
fail_count="$(grep -m1 '"fail"' "${LOCAL_STATUS}" | sed 's/.*"fail": \([0-9]*\).*/\1/')"
printf '{"timestamp":"%s","overall":"%s","fail":%s}\n' "${ts}" "${overall}" "${fail_count:-0}" > "${LOCAL_HISTORY}"

scp ${SSH_OPTS} -i "${LXC_KEY}" "${LOCAL_HISTORY}" "${LXC_TARGET}:${LXC_DIR}/history-append.jsonl"
ssh ${SSH_OPTS} -i "${LXC_KEY}" "${LXC_TARGET}" \
  "mkdir -p '${LXC_DIR}' && cat '${LXC_DIR}/history-append.jsonl' >> '${LXC_DIR}/history.jsonl' && rm -f '${LXC_DIR}/history-append.jsonl' && tail -n 480 '${LXC_DIR}/history.jsonl' > '${LXC_DIR}/history.jsonl.tmp' && mv '${LXC_DIR}/history.jsonl.tmp' '${LXC_DIR}/history.jsonl'"
