#!/bin/bash
# Inspect /sys/class/power_supply and find a way to cap the battery
# charge on joyeuse. Different mainline charger drivers expose different
# interfaces; this script just dumps everything writable plus the
# important read-only fields so we can plan the actual limiter.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/../phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== /sys/class/power_supply/ entries ==="
ls /sys/class/power_supply/
echo
for ps in /sys/class/power_supply/*; do
    name=$(basename "$ps")
    echo "------ $name ------"
    echo "  type     : $(cat "$ps/type" 2>/dev/null)"
    echo "  status   : $(cat "$ps/status" 2>/dev/null)"
    echo "  online   : $(cat "$ps/online" 2>/dev/null)"
    echo "  capacity : $(cat "$ps/capacity" 2>/dev/null)"
    echo "  ...writable files..."
    find "$ps" -maxdepth 1 -type f -writable 2>/dev/null
    echo "  ...interesting read-only files..."
    for f in $ps/charge_control_limit $ps/charge_control_limit_max \
             $ps/charge_control_start_threshold $ps/charge_control_end_threshold \
             $ps/current_max $ps/constant_charge_current $ps/constant_charge_current_max \
             $ps/voltage_max $ps/voltage_now $ps/current_now \
             $ps/input_current_limit $ps/input_voltage_limit; do
        [ -e "$f" ] && echo "    $(basename "$f")=$(cat "$f" 2>/dev/null)"
    done
done
echo
echo "=== uevent of any battery ==="
for ps in /sys/class/power_supply/*; do
    if [ "$(cat "$ps/type" 2>/dev/null)" = "Battery" ]; then
        echo "----- $(basename "$ps") uevent -----"
        cat "$ps/uevent" 2>/dev/null
    fi
done
echo
echo "=== apk world for charging tools ==="
apk search -e acca pmos-charge-limit upower 2>/dev/null'
