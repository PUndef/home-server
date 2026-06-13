#!/bin/bash
# Flash v25.12 images to joyeuse in fastboot mode.
# DESTRUCTIVE — wipes cache, userdata, boot.
#
# Prerequisites:
#   - Phone in fastboot (Vol-Down + Power), USB to host running this script
#   - fastboot devices shows one device
#   - fastboot getvar product → joyeuse (or curtana/excalibur — miatoll family)
#
# Usage (on build host, e.g. Proxmox):
#   ARTIFACT_DIR=/root/pmos-artifacts bash flash-fastboot.sh

set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-$HOME/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs}"
BOOT_IMG="${ARTIFACT_DIR}/xiaomi-miatoll-boot.img"
ROOT_IMG="${ARTIFACT_DIR}/xiaomi-miatoll-root.img"
UBOOT_IMG="${ARTIFACT_DIR}/u-boot-sm7125.img"

for f in "$BOOT_IMG" "$ROOT_IMG" "$UBOOT_IMG"; do
    [ -f "$f" ] || { echo "missing: $f"; exit 1; }
done

echo "=== fastboot devices ==="
fastboot devices
product="$(fastboot getvar product 2>&1 | awk '/product:/{print $2}')"
echo "product=$product"
case "$product" in
    joyeuse|curtana|excalibur|gram|*) ;;
esac

read -r -p "Flash will WIPE cache/userdata/boot. Continue? [y/N] " ans
[ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1

fastboot flash cache    "$BOOT_IMG"
fastboot flash userdata "$ROOT_IMG"
fastboot erase dtbo
fastboot flash boot     "$UBOOT_IMG"
fastboot reboot

echo "Flashed. First boot 1–5 min. Connect Wi-Fi, then post-flash-setup.sh"
