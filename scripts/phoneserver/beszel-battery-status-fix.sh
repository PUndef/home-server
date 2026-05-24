#!/bin/sh
# Work around Beszel 0.18.x ignoring batteries when power_supply status is
# "Unknown" (common with Qualcomm qcom_qg on postmarketOS).
#
# Infers Charging vs Discharging from USB online and bind-mounts a fake
# status file before beszel-agent reads sysfs. Install via
# install-beszel-battery-fix.sh (OpenRC start_pre hook).

set -eu

PS_BAT="/sys/class/power_supply/qcom_qg"
PS_USB="/sys/class/power_supply/tcpm-source-psy-c440000.spmi:pmic@0:typec@1500"
RUN_DIR="/run/beszel-battery-fix"
FAKE_STATUS="${RUN_DIR}/status"

[ -d "${PS_BAT}" ] || exit 0

cur="$(cat "${PS_BAT}/status" 2>/dev/null || true)"
case "${cur}" in
    Charging|Discharging|Full|Empty|"Not charging") exit 0 ;;
esac

mkdir -p "${RUN_DIR}"
usb_online="$(cat "${PS_USB}/online" 2>/dev/null || echo 0)"
if [ "${usb_online}" = "1" ]; then
    echo Charging > "${FAKE_STATUS}"
else
    echo Discharging > "${FAKE_STATUS}"
fi

if mountpoint -q "${PS_BAT}/status" 2>/dev/null; then
    mount --bind "${FAKE_STATUS}" "${PS_BAT}/status" 2>/dev/null || true
else
    mount --bind "${FAKE_STATUS}" "${PS_BAT}/status"
fi
