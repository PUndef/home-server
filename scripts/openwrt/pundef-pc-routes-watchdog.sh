#!/bin/sh
# Self-heal pundef-pc routes if catch-all reappears or policies drift.
# Installed to /opt/pundef-pc-routes-watchdog.sh by apply_pundef_pc_routes.py --install-cron

APPLY="/opt/apply-pundef-pc-routes.sh"
[ -x "${APPLY}" ] || APPLY="/opt/apply-pundef-pc-routes.sh"

if [ -f /etc/destiny-login-mode ]; then
  exit 0
fi

if [ ! -f "${APPLY}" ]; then
  exit 0
fi

if sh "${APPLY}" --check-only >/dev/null 2>&1; then
  exit 0
fi

logger -t pundef-pc-routes "drift detected — reapplying canonical routes"
sh "${APPLY}" >/dev/null 2>&1
