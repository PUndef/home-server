#!/usr/bin/env bash
# Hosts fix + OwnCord Kuma monitors on phoneserver (no Kuma API password needed).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "${SCRIPT_DIR}/run-fix-kuma-remote.sh"
