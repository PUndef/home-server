#!/bin/bash
# Expand the ext4 root filesystem on /dev/sda18 (userdata partition) to the
# full partition size. pmbootstrap initially formats it ~650 MiB; on joyeuse
# the userdata partition is ~105 GiB.
#
# Online resize, safe to run on a mounted /.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/../phone-defaults.sh"
SUDO_PASS=${SUDO_PASS:-changemenow}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "echo === before ===
df -h /
echo
echo === resize2fs ===
echo '$SUDO_PASS' | sudo -S resize2fs /dev/sda18 2>&1 | tail -5
echo
echo === after ===
df -h /"
