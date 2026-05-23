#!/bin/bash
# Build a custom Android-style boot.img (header v2) for joyeuse from
# pmOS artefacts. Runs through `pmbootstrap chroot` because the native
# chroot has the working `mkbootimg-osm0sis` package; the Ubuntu/PyPI
# mkbootimg is broken (missing gki module).
#
# Source artefacts come from the freshly built pmOS rootfs.
# Output:
#   ~/.local/var/pmbootstrap/chroot_native/home/pmos/pmos-joyeuse-test.img
#
# Offsets are stock for SM7125 / SD720G devices (taken from existing
# downstream MIUI fastboot logs).
set -e

STAGE=/tmp/joyeuse-boot
mkdir -p "$STAGE"
cd "$STAGE"

echo "=== extract kernel + initramfs + DTBs from pmOS rootfs ==="
pmbootstrap chroot --rootfs -- cat /boot/vmlinuz   > vmlinuz
pmbootstrap chroot --rootfs -- cat /boot/initramfs > initramfs
pmbootstrap chroot --rootfs -- cat /boot/dtbs/qcom/sm7125-xiaomi-joyeuse-tianma.dtb  > sm7125-tianma.dtb
pmbootstrap chroot --rootfs -- cat /boot/dtbs/qcom/sm7125-xiaomi-joyeuse-huaxing.dtb > sm7125-huaxing.dtb

echo "=== unwrap EFI zboot wrapper -> raw Image ==="
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/extract-kernel-from-zboot.py" vmlinuz Image

echo "=== concat both joyeuse DTBs (bootloader picks the right one) ==="
cat sm7125-tianma.dtb sm7125-huaxing.dtb > both.dtb

echo "=== stage files into pmbootstrap native chroot ==="
CHROOT_HOME=~/.local/var/pmbootstrap/chroot_native/home/pmos
sudo cp Image initramfs both.dtb "$CHROOT_HOME/"
sudo chown -R 12345:12345 "$CHROOT_HOME"/{Image,initramfs,both.dtb}

echo "=== run mkbootimg inside chroot ==="
pmbootstrap chroot -- /bin/sh -c "
cd /home/pmos
mkbootimg \
    --kernel Image \
    --ramdisk initramfs \
    --dtb both.dtb \
    --base 0 \
    --kernel_offset 0x00200000 \
    --ramdisk_offset 0x01000000 \
    --tags_offset 0x00000100 \
    --dtb_offset 0x01F00000 \
    --pagesize 4096 \
    --header_version 2 \
    --os_version 11.0.0 \
    --os_patch_level 2020-06 \
    --cmdline 'console=null no_console_suspend earlycon ignore_loglevel PMOS_NO_OUTPUT_REDIRECT' \
    -o pmos-joyeuse-test.img
ls -la pmos-joyeuse-test.img
"

echo "=== resulting image ==="
ls -la "$CHROOT_HOME/pmos-joyeuse-test.img"
