#!/bin/bash
# Build postmarketOS v25.12 headless image for joyeuse (xiaomi-miatoll).
# Run on a Linux host with network (Proxmox or WSL). Not on the phone.
#
# Outputs:
#   ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-boot.img
#   ~/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/xiaomi-miatoll-root.img
# Plus u-boot-sm7125.img from asidko release (downloaded separately).
#
# Usage:
#   bash scripts/phoneserver/migrate-v2512/build-headless.sh

set -euo pipefail

PMB_CMD=()
if [ -n "${PMBOOTSTRAP:-}" ]; then
    # shellcheck disable=SC2206
    PMB_CMD=($PMBOOTSTRAP)
else
    PMB_CMD=(pmbootstrap)
fi
if [ "$(id -u)" -eq 0 ] && [[ " ${PMB_CMD[*]} " != *" --as-root "* ]]; then
    PMB_CMD+=(--as-root)
fi
pmb() { "${PMB_CMD[@]}" "$@"; }
CHANNEL="${PMBOOTSTRAP_CHANNEL:-v25.12}"
BOOT_SIZE="${PMBOOTSTRAP_BOOT_SIZE:-256}"
WORKDIR="${PMBOOTSTRAP_WORK:-$HOME/.local/var/pmbootstrap}"
ROOTFS_DIR="${WORKDIR}/chroot_native/home/pmos/rootfs"
PMAP_PORTS="${WORKDIR}/cache_git/pmaports"
UBOOT_OUT="${ROOTFS_DIR}/u-boot-sm7125.img"
UBOOT_URL="https://github.com/asidko/redmi-note-9s-postmarketos/releases/latest/download/u-boot-sm7125.img"

patch_boot_size_check() {
    local py
    py="$(python3 -c 'import pmb.install._install as i, os; print(os.path.dirname(i.__file__))' 2>/dev/null)/_install.py"
    if [ ! -f "$py" ]; then
        echo "[build] WARN: cannot find pmb/install/_install.py — boot_size patch skipped"
        return 0
    fi
    if grep -q 'patched for joyeuse' "$py"; then
        echo "[build] boot_size sanity check already patched"
        return 0
    fi
    sed -i 's|if int(config.boot_size) >= int(default):|if True:  # patched for joyeuse 384MB cache|' "$py"
    echo "[build] patched boot_size sanity check in $py"
}

ensure_pmaports() {
    mkdir -p "${WORKDIR}/cache_git"
    if [ ! -d "${PMAP_PORTS}/.git" ]; then
        git clone --depth 1 --branch "${CHANNEL}" \
            https://gitlab.postmarketos.org/postmarketOS/pmaports.git "${PMAP_PORTS}"
    else
        git -C "${PMAP_PORTS}" fetch origin "${CHANNEL}" --depth 1
        git -C "${PMAP_PORTS}" checkout -f "${CHANNEL}"
    fi
}

configure_pmbootstrap() {
    if [ ! -f "${HOME}/.config/pmbootstrap_v3.cfg" ]; then
        echo "[build] ERROR: missing ~/.config/pmbootstrap_v3.cfg — run pmbootstrap init first"
        exit 1
    fi
    pmb config device xiaomi-miatoll
    # v25.12: unified linux-postmarketos-qcom-sm7125 (6.14.7), no joyeuse_tianma subpackage.
    # PD panel DTB is applied later via asidko install-asidko-charger-v062.sh.
    pmb config ui none
    pmb config user pmos
    pmb config hostname phoneserver
    pmb config boot_size "${BOOT_SIZE}"
    pmb config build_pkgs_on_install false
    pmb config timezone Asia/Krasnoyarsk
    pmb config locale C.UTF-8
}

patch_plymouth_cmdline() {
    local boot_img="${ROOTFS_DIR}/xiaomi-miatoll-boot.img"
    local mnt
    if [ ! -f "$boot_img" ]; then
        echo "[build] WARN: $boot_img missing — skip Plymouth cmdline patch"
        return 0
    fi
    mnt="$(mktemp -d)"
    cleanup() { umount "$mnt" 2>/dev/null || true; rmdir "$mnt" 2>/dev/null || true; }
    trap cleanup EXIT
    mount -o loop "$boot_img" "$mnt"
    local entry="${mnt}/loader/entries/pmos.conf"
    if [ ! -f "$entry" ]; then
        echo "[build] WARN: no $entry — skip Plymouth patch"
        return 0
    fi
    sed -i \
        -e 's/quiet loglevel=2/plymouth.enable=0 console=tty0 systemd.show_status=true loglevel=7/' \
        -e 's/ quiet//g' \
        "$entry"
    echo "[build] patched Plymouth/cmdline in pmos.conf"
    umount "$mnt"
    trap - EXIT
    rmdir "$mnt"
}

download_uboot() {
    mkdir -p "${ROOTFS_DIR}"
    if [ -f "${UBOOT_OUT}" ]; then
        echo "[build] u-boot already at ${UBOOT_OUT}"
        return 0
    fi
    curl -fL -o "${UBOOT_OUT}" "${UBOOT_URL}"
    ls -lah "${UBOOT_OUT}"
}

echo "[build] === phoneserver v25.12 headless build ==="
patch_boot_size_check
ensure_pmaports
configure_pmbootstrap

echo "[build] pmaports channel: ${CHANNEL}"
echo "[build] starting pmbootstrap install (may take 30–90 min)..."
pmb install --no-fde --password changemenow --split

patch_plymouth_cmdline
download_uboot

echo "[build] === artifacts ==="
ls -lah "${ROOTFS_DIR}/xiaomi-miatoll-boot.img" \
         "${ROOTFS_DIR}/xiaomi-miatoll-root.img" \
         "${UBOOT_OUT}"
