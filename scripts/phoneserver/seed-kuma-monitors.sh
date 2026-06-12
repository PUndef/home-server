#!/usr/bin/env bash
# Seed Uptime Kuma monitors from kuma-monitors.json.
#
# Prerequisites:
#   - Admin account created in Kuma UI (http://192.168.50.35:3001/)
#   - Creates scripts/phoneserver/.venv-kuma on first run (PEP 668 safe)
#
# Usage:
#   KUMA_USERNAME=admin KUMA_PASSWORD='...' ./seed-kuma-monitors.sh
#   KUMA_USERNAME=admin KUMA_PASSWORD='...' ./seed-kuma-monitors.sh --dry-run

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SCRIPT_DIR="${REPO_ROOT}/scripts/phoneserver"
SCRIPT="${SCRIPT_DIR}/seed-kuma-monitors.py"
VENV="${SCRIPT_DIR}/.venv-kuma"
KUMA_URL="${KUMA_URL:-http://192.168.50.35:3001}"

if [[ -z "${KUMA_USERNAME:-}" || -z "${KUMA_PASSWORD:-}" ]]; then
    echo "usage: KUMA_USERNAME=admin KUMA_PASSWORD='...' $0 [--dry-run]" >&2
    exit 2
fi

KUMA_PKG="uptime-kuma-api-v2"

if [[ ! -x "${VENV}/bin/python" ]]; then
    echo "creating venv ${VENV}"
    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" install -q --upgrade pip
    "${VENV}/bin/pip" install -q "${KUMA_PKG}"
elif ! "${VENV}/bin/python" -c "from uptime_kuma_api.__version__ import __title__; assert __title__ == 'uptime_kuma_api_v2'" 2>/dev/null; then
    echo "upgrading venv to ${KUMA_PKG} (Kuma 2.x; lucasheld/uptime-kuma-api is 1.x only)..."
    "${VENV}/bin/pip" uninstall -y uptime-kuma-api 2>/dev/null || true
    "${VENV}/bin/pip" install -q "${KUMA_PKG}"
fi

export KUMA_URL
exec "${VENV}/bin/python" "${SCRIPT}" "$@"
