#!/bin/bash
# Flip USB-C port from source (default on this mainline build) to sink so
# the phone can be charged via the cable instead of trying to power the host.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/../phone-defaults.sh"
SUDO_PASS=${SUDO_PASS:-changemenow}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "${SSH_REMOTE}" \
    "echo === before ===
cat /sys/class/typec/port0/{port_type,power_role,data_role}
cat /sys/class/power_supply/qcom_qg/{capacity,current_now}
cat /sys/class/power_supply/tcpm-source-psy-c440000.spmi:pmic@0:typec@1500/{online,current_max} 2>/dev/null
echo
echo === flipping to sink ===
echo '$SUDO_PASS' | sudo -S sh -c '
    echo sink > /sys/class/typec/port0/port_type 2>&1
    echo sink > /sys/class/typec/port0/power_role 2>&1
'
sleep 4
echo
echo === after ===
cat /sys/class/typec/port0/{port_type,power_role,data_role}
cat /sys/class/power_supply/qcom_qg/{capacity,current_now,status}
cat /sys/class/power_supply/tcpm-source-psy-c440000.spmi:pmic@0:typec@1500/{online,current_max} 2>/dev/null"
