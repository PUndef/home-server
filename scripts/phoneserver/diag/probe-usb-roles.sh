#!/bin/bash
PHONE_IP=${PHONE_IP:-172.16.42.1}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
SUDO_PASS=${SUDO_PASS:-changemenow}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "echo '=== /sys/class/typec/port0 contents ==='
ls -la /sys/class/typec/port0/ 2>/dev/null
echo
echo '=== port0 capabilities/permissions ==='
for f in /sys/class/typec/port0/*; do
    [ -f \"\$f\" ] && ls -la \"\$f\" 2>/dev/null
done
echo
echo '=== usb_role class ==='
ls /sys/class/usb_role/ 2>/dev/null
for r in /sys/class/usb_role/*/role; do
    [ -e \"\$r\" ] && echo \"\$r = \$(cat \$r)\"
done
echo
echo '=== role.* sysfs anywhere ==='
find /sys/class -name 'role' -o -name 'port_type' -o -name 'power_role' 2>/dev/null
echo
echo '=== try dual instead of sink (root in shell) ==='
echo '$SUDO_PASS' | sudo -S sh -c '
    for v in dual sink source; do
        for f in /sys/class/typec/port0/port_type /sys/class/typec/port0/power_role; do
            echo \"--> writing \$v to \$f\"
            echo \"\$v\" > \"\$f\" 2>&1 && echo OK || echo FAILED
        done
    done
'
echo
echo '=== usb-role-switch on udc/usb ==='
for r in /sys/bus/platform/devices/*role*/role; do
    [ -e \"\$r\" ] && echo \"\$r => \$(cat \$r)\"
done
echo
echo '=== current type-c rev / supported_accessory_modes / preferred_role ==='
cat /sys/class/typec/port0/usb_typec_revision 2>/dev/null
cat /sys/class/typec/port0/supported_accessory_modes 2>/dev/null
cat /sys/class/typec/port0/preferred_role 2>/dev/null"
