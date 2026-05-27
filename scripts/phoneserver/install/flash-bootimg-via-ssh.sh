#!/bin/bash
# Push a fresh Android-style boot.img to phoneserver over SSH and dd it into
# /dev/disk/by-partlabel/boot. Avoids round-tripping through fastboot mode
# every time we tweak the kernel/DTB/cmdline.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/../phone-defaults.sh"
SUDO_PASS=${SUDO_PASS:-changemenow}
BOOT_IMG=${BOOT_IMG:-$HOME/.local/var/pmbootstrap/chroot_native/home/pmos/pmos-joyeuse-test.img}

echo "=== using boot.img: $BOOT_IMG ==="
ls -la "$BOOT_IMG"

echo "=== upload to phone /tmp ==="
scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "$BOOT_IMG" "pmos@${PHONE_IP}:/tmp/pmos-boot.img"

echo "=== dd to /dev/disk/by-partlabel/boot ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "echo '$SUDO_PASS' | sudo -S sh -c 'dd if=/tmp/pmos-boot.img of=/dev/disk/by-partlabel/boot bs=1M conv=fsync && sync'"

echo "=== verify ANDROID! magic ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "echo '$SUDO_PASS' | sudo -S sh -c 'head -c 16 /dev/disk/by-partlabel/boot | xxd'"

echo "Done. Reboot with: ssh -i $SSH_KEY pmos@${PHONE_IP} 'sudo reboot'"
