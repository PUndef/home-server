#!/bin/bash
# Flash asidko v25.12 prebuilt images to joyeuse (miatoll partition layout).
# DESTRUCTIVE. Phone in fastboot, USB connected.
#
#   ARTIFACT_DIR=/root/pmos-artifacts/asidko bash flash-asidko-prebuilt.sh

set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-/root/pmos-artifacts/asidko}"
BOOT_IMG="${ARTIFACT_DIR}/xiaomi-miatoll-boot.img"
ROOT_IMG="${ARTIFACT_DIR}/xiaomi-miatoll-root.img"
UBOOT_IMG="${ARTIFACT_DIR}/u-boot-sm7125.img"

for f in "$BOOT_IMG" "$ROOT_IMG" "$UBOOT_IMG"; do
    [ -f "$f" ] || { echo "missing: $f — run download-asidko-prebuilt.sh"; exit 1; }
done

echo "=== fastboot devices ==="
fastboot devices
product="$(fastboot getvar product 2>&1 | awk '/product:/{print $2}')"
echo "product=$product (expect joyeuse; curtana/excalibur also miatoll family)"

read -r -p "WIPE cache/userdata/boot and flash? [y/N] " ans
[ "$ans" = "y" ] || [ "$ans" = "Y" ] || exit 1

# miatoll: cache=kernel+bootpart, boot=U-Boot — NEVER flash boot.img to boot!
fastboot flash cache    "$BOOT_IMG"
fastboot flash userdata "$ROOT_IMG"
fastboot erase dtbo
fastboot flash boot     "$UBOOT_IMG"
fastboot reboot

echo "First boot 1–5 min. Default: user/1234, hostname redmi — run post-flash-headless.sh after Wi-Fi."
