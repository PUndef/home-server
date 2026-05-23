#!/bin/bash
# Find out why USB charging is not active on joyeuse mainline.

PHONE_IP=${PHONE_IP:-172.16.42.1}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
SUDO_PASS=${SUDO_PASS:-changemenow}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "echo '=== dmesg | grep charger / pd / typec / pm6150 ==='
echo '$SUDO_PASS' | sudo -S dmesg 2>/dev/null | grep -iE 'charg|tcpm|typec|pm6150|smb|pd_|pmic_glink|extcon|usb-c' | head -40
echo
echo '=== loaded modules touching charging ==='
echo '$SUDO_PASS' | sudo -S lsmod | grep -iE 'tcpm|typec|smb|qcom_pmic|pm6150|charg|qcom_battmgr|pd_|extcon'
echo
echo '=== tcpm-source uevent ==='
ps=\$(ls -d /sys/class/power_supply/tcpm-source* 2>/dev/null | head -1)
[ -n \"\$ps\" ] && cat \"\$ps/uevent\"
echo
echo '=== type-c port state ==='
ls /sys/class/typec/ 2>/dev/null
for p in /sys/class/typec/port*; do
    [ -d \"\$p\" ] || continue
    echo \"--- \$p ---\"
    for k in data_role power_role port_type vconn_source orientation power_operation_mode; do
        [ -e \"\$p/\$k\" ] && echo \"  \$k = \$(cat \$p/\$k)\"
    done
done
echo
echo '=== pmic-glink ==='
ls /sys/devices/platform/ 2>/dev/null | grep -iE 'pmic|smb|glink' | head
echo
echo '=== qcom_battmgr or similar power-supply nodes ==='
for ps in /sys/class/power_supply/*; do echo \"\$ps: type=\$(cat \$ps/type 2>/dev/null)\"; done
echo
echo '=== usb-c port driver in /sys ==='
find /sys/bus -name '*typec*' 2>/dev/null | head -10"
