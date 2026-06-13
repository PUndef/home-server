#!/bin/sh
# Repack Android boot.img on joyeuse (v25.06 fastboot scheme) with PD Type-C DTB.
# Run on phoneserver as root.
set -eu

PD_DTB="${PD_DTB:-/boot/dtbs/qcom/sm7125-xiaomi-joyeuse-tianma-pd.dtb}"
BOOT_PART="${BOOT_PART:-/dev/disk/by-partlabel/boot}"
WORKDIR="${WORKDIR:-/tmp/boot-repack}"

log() { printf '[boot-pd] %s\n' "$*"; }

[ -f "$PD_DTB" ] || { log "PD DTB missing: $PD_DTB"; exit 1; }

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/unpacked"
cd "$WORKDIR"

log "dumping $BOOT_PART -> boot-current.img"
dd if="$BOOT_PART" of=boot-current.img bs=1M conv=fsync status=none

log "unpacking boot.img"
unpackbootimg -i boot-current.img -o unpacked 2>&1 | tee unpack-info.txt

PREFIX="unpacked/boot-current.img"
RAMDISK="${PREFIX}-ramdisk"
LINUX_TREE="${LINUX_TREE:-/root/linux}"

[ -f "$RAMDISK" ] || { log "ramdisk blob not found: $RAMDISK"; ls -la unpacked/; exit 1; }

# joyeuse v25.06: deviceinfo_append_dtb=true, header v0 — DTB catenated after Image.
SRC_KERNEL="${PREFIX}-kernel"
KERNEL="$WORKDIR/kernel-with-pd.dtb"
log "swap appended DTB in extracted kernel ($(wc -c < "$SRC_KERNEL") bytes)"
python3 - "$SRC_KERNEL" "$PD_DTB" "$KERNEL" <<'PY'
import sys
src, pd, out = sys.argv[1:4]
data = open(src, "rb").read()
magic = b"\xd0\x0d\xfe\xed"
idx = data.rfind(magic)
if idx < 0:
    sys.exit("FDT magic not found in kernel blob")
open(out, "wb").write(data[:idx] + open(pd, "rb").read())
print(f"stripped old dtb at offset {idx}, wrote {out}")
PY

# unpackbootimg prints BOARD_* lines (osm0sis fork).
read_hex() { sed -n "s/^$1 0x\\([0-9a-fA-F]*\\).*/\\1/p" unpack-info.txt | head -1; }
read_val() { sed -n "s/^$1 \\([0-9]*\\).*/\\1/p" unpack-info.txt | head -1; }

BASE=$(read_hex BOARD_KERNEL_BASE)
KOFF=$(read_hex BOARD_KERNEL_OFFSET)
ROFF=$(read_hex BOARD_RAMDISK_OFFSET)
SOFF=$(read_hex BOARD_SECOND_OFFSET)
TOFF=$(read_hex BOARD_TAGS_OFFSET)
PAGE=$(read_val BOARD_PAGE_SIZE)
HVER=$(read_val BOARD_HEADER_VERSION)
CMDLINE=$(sed -n 's/^BOARD_KERNEL_CMDLINE //p' unpack-info.txt | head -1)

[ -n "$BASE" ] || BASE=0
[ -n "$PAGE" ] || PAGE=4096
[ -n "$HVER" ] || HVER=0

log "repacking boot.img (kernel+dtb $(wc -c < "$KERNEL") bytes)"
MKARGS="--kernel $KERNEL --ramdisk $RAMDISK"
MKARGS="$MKARGS --base 0x$BASE --pagesize $PAGE --header_version $HVER"
[ -n "$KOFF" ] && MKARGS="$MKARGS --kernel_offset 0x$KOFF"
[ -n "$ROFF" ] && MKARGS="$MKARGS --ramdisk_offset 0x$ROFF"
[ -n "$SOFF" ] && MKARGS="$MKARGS --second_offset 0x$SOFF"
[ -n "$TOFF" ] && MKARGS="$MKARGS --tags_offset 0x$TOFF"
[ -n "$CMDLINE" ] && MKARGS="$MKARGS --cmdline \"$CMDLINE\""
MKARGS="$MKARGS -o boot-pd.img"

# shellcheck disable=SC2086
eval mkbootimg-osm0sis $MKARGS

NEW_SIZE=$(wc -c < boot-pd.img)
PART_SIZE=$(blockdev --getsize64 "$BOOT_PART")
[ "$NEW_SIZE" -le "$PART_SIZE" ] || { log "new boot.img too large ($NEW_SIZE > $PART_SIZE)"; exit 1; }

cp -a "$BOOT_PART" "${BOOT_PART}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || \
    dd if="$BOOT_PART" of="/tmp/boot-part.bak.$(date +%Y%m%d%H%M%S)" bs=1M conv=fsync status=none

log "flashing boot-pd.img -> $BOOT_PART"
dd if=boot-pd.img of="$BOOT_PART" bs=1M conv=fsync status=none
sync

log "done. new boot.img size: $NEW_SIZE bytes"
head -c 8 boot-pd.img | od -An -tx1
