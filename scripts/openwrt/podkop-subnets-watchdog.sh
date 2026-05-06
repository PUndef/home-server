#!/bin/sh

LOCK_FILE="/tmp/podkop-subnets-watchdog.lock"
LOG_TAG="podkop-watchdog"

[ -e "$LOCK_FILE" ] && exit 0
touch "$LOCK_FILE"
trap 'rm -f "$LOCK_FILE"' EXIT

if ! nft list set inet PodkopTable podkop_subnets >/tmp/podkop-subnets-watchdog.nft 2>/dev/null; then
  logger -t "$LOG_TAG" "PodkopTable/podkop_subnets not found; skip"
  exit 0
fi

if grep -q "elements = {" /tmp/podkop-subnets-watchdog.nft; then
  exit 0
fi

logger -t "$LOG_TAG" "podkop_subnets is empty, running podkop list_update"
/usr/bin/podkop list_update >/tmp/podkop-subnets-watchdog.update.log 2>&1
RC=$?
logger -t "$LOG_TAG" "podkop list_update finished with rc=$RC"

exit 0
