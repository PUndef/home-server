#!/bin/sh
# Self-heal empty pbr_workvpn table while workvpn is up.
# Without a default route there, corp clients (paul-mac / pundef-pc / phone)
# get fwmark 0x30000 but packets blackhole in table pbr_workvpn.
#
# Cron on router: */5 * * * * /opt/pbr-workvpn-watchdog.sh

LOCK_FILE="/tmp/pbr-workvpn-watchdog.lock"
LOG_TAG="pbr-workvpn-watchdog"

[ -e "$LOCK_FILE" ] && exit 0
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

if ! ifstatus workvpn | grep -q '"up": true'; then
  exit 0
fi

if ip route show table pbr_workvpn | grep -q 'default via .* dev vpn-workvpn'; then
  exit 0
fi

logger -t "$LOG_TAG" "pbr_workvpn table empty while workvpn is up; restarting pbr"
/etc/init.d/pbr restart
RC=$?
sh /opt/seed-phoneserver-groq-ips.sh 2>/dev/null || true
logger -t "$LOG_TAG" "pbr restart finished with rc=$RC"

exit 0
