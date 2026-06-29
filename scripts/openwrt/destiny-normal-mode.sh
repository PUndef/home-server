#!/bin/sh
# Restore normal routes: Steam -> WAN, Destiny -> awg2
#
# Usage:
#   sh destiny-normal-mode.sh
# From PC:
#   py -3 scripts/openwrt/apply_overrides.py --mode normal

set -eu

FLAG="/etc/destiny-login-mode"
APPLY="/opt/apply-pundef-pc-routes.sh"

rm -f "${FLAG}"

if [ -x "${APPLY}" ]; then
  sh "${APPLY}"
elif [ -f "${APPLY}" ]; then
  sh "${APPLY}"
else
  echo "ERROR: ${APPLY} missing — run apply_overrides.py --mode normal from PC" >&2
  exit 1
fi

echo "=== normal mode: Steam -> WAN, Destiny -> awg2 ==="
