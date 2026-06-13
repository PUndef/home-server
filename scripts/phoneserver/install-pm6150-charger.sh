#!/bin/sh
# Build and install asidko/pm6150-charger-mainline on joyeuse (pmOS v25.06, 6.12.1-sm7125).
# Does NOT reflash userdata. Adds OOT kernel modules + optional late-load hook (OpenRC).
#
# Usage (on phoneserver as pmos, or via SSH):
#   bash install-pm6150-charger.sh
#   bash install-pm6150-charger.sh --with-pd-dtb   # also install PD DTB (reboot required)

set -eu

WITH_PD_DTB=0
[ "${1:-}" = "--with-pd-dtb" ] && WITH_PD_DTB=1

KREL="$(uname -r)"
# Tag sm7125-6.12.1 on sm7125-mainline/linux (matches pmaports v25.06 joyeuse_tianma).
KERNEL_COMMIT=c08ea478e5dbea11f672f4b57c4fa8ab54257c99
LOCALVER=
HOME_DIR="${HOME:-/home/pmos}"
LINUX_DIR="${HOME_DIR}/linux"
CHGR_REPO="${HOME_DIR}/pm6150-charger-mainline"
BACKUP_DIR="${HOME_DIR}/backups"
HA_CONFIG=/opt/homeassistant/config

log() { printf '[pm6150-chgr] %s\n' "$*"; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        exec sudo "$0" "$@"
    fi
}

backup_ha() {
    if [ ! -d "${HA_CONFIG}" ]; then
        log "no HA config at ${HA_CONFIG}, skip backup"
        return 0
    fi
    mkdir -p "${BACKUP_DIR}"
    stamp="$(date +%Y%m%d-%H%M%S)"
    out="${BACKUP_DIR}/homeassistant-config-${stamp}.tar.gz"
    log "backing up HA config -> ${out}"
    tar czf "${out}" -C /opt/homeassistant config
    log "HA backup size: $(du -h "${out}" | awk '{print $1}')"
}

install_deps() {
    log "installing build dependencies"
    apk add --no-cache build-base git bc bison flex elfutils-dev openssl-dev perl \
        xz python3
}

clone_sources() {
    if [ ! -d "${LINUX_DIR}/.git" ]; then
        log "fetching sm7125-mainline/linux@${KERNEL_COMMIT} (shallow, ~200MB not full 5GB clone)"
        mkdir -p "${LINUX_DIR}"
        git -C "${LINUX_DIR}" init
        git -C "${LINUX_DIR}" remote add origin https://github.com/sm7125-mainline/linux.git
    fi
    log "checking out kernel ${KERNEL_COMMIT}"
    git -C "${LINUX_DIR}" fetch --depth 1 origin "${KERNEL_COMMIT}"
    git -C "${LINUX_DIR}" checkout -f FETCH_HEAD

    if [ ! -d "${CHGR_REPO}/.git" ]; then
        log "cloning pm6150-charger-mainline"
        git clone https://github.com/asidko/pm6150-charger-mainline.git "${CHGR_REPO}"
    else
        git -C "${CHGR_REPO}" pull --ff-only
    fi
}

progress() {
    log "$*"
}

prepare_kernel_tree() {
    log "preparing kernel tree (modules_prepare, ~3-8 min on phone)"
    if [ -f /proc/config.gz ]; then
        zcat /proc/config.gz > "${LINUX_DIR}/.config"
    elif [ -f "${LINUX_DIR}/arch/arm64/configs/sm7125.config" ]; then
        log "no /proc/config.gz; using arch/arm64/configs/sm7125.config"
        cp "${LINUX_DIR}/arch/arm64/configs/sm7125.config" "${LINUX_DIR}/.config"
    else
        log "no kernel config source found"
        exit 1
    fi
    make -C "${LINUX_DIR}" ARCH=arm64 LOCALVERSION="${LOCALVER}" olddefconfig
    make -C "${LINUX_DIR}" ARCH=arm64 LOCALVERSION="${LOCALVER}" -j"$(nproc)" modules_prepare
}

build_modules() {
    log "applying qcom_qg patch"
    git -C "${LINUX_DIR}" checkout -- drivers/power/supply/qcom_qg.c 2>/dev/null || true
    patch -d "${LINUX_DIR}" -p1 -N < "${CHGR_REPO}/patches/0001-power-supply-qcom_qg-expose-SCOPE-Device.patch"

    log "building patched qcom_qg.ko"
    make -C "${LINUX_DIR}" ARCH=arm64 LOCALVERSION="${LOCALVER}" KBUILD_MODPOST_WARN=1 \
        drivers/power/supply/qcom_qg.ko

    for mod in joyeuse_battery_shim pm6150_chgr_minimal; do
        log "building ${mod}.ko"
        make -C "${CHGR_REPO}/kernel/${mod}" clean
        make -C "${CHGR_REPO}/kernel/${mod}" KDIR="${LINUX_DIR}" ARCH=arm64 \
            LOCALVERSION="${LOCALVER}" KBUILD_MODPOST_WARN=1
    done
}

install_modules() {
    extra="/lib/modules/${KREL}/extra"
    qg="/lib/modules/${KREL}/kernel/drivers/power/supply/qcom_qg.ko"
    mkdir -p "${extra}"
    cp -a "${qg}" "${qg}.stock-backup" 2>/dev/null || true
    install -m644 "${LINUX_DIR}/drivers/power/supply/qcom_qg.ko" "${qg}"
    install -m644 "${CHGR_REPO}/kernel/joyeuse_battery_shim/joyeuse_battery_shim.ko" \
        "${extra}/joyeuse_battery_shim.ko"
    install -m644 "${CHGR_REPO}/kernel/pm6150_chgr_minimal/pm6150_chgr_minimal.ko" \
        "${extra}/pm6150_chgr_minimal.ko"
    depmod -a
}

install_openrc_hook() {
    log "installing OpenRC late-load hook"
    cat > /etc/local.d/pm6150_charger.start <<'EOF'
#!/bin/sh
# Load PM6150 charger stack after qcom_qg appears (joyeuse / pmOS OpenRC).
modprobe -r pm6150_chgr_minimal joyeuse_battery_shim 2>/dev/null || true
modprobe -r qcom_qg 2>/dev/null || true
modprobe qcom_qg
modprobe joyeuse_battery_shim
i=0
while [ ! -e /sys/class/power_supply/qcom_qg ] && [ "$i" -lt 50 ]; do
    sleep 0.2
    i=$((i + 1))
done
modprobe pm6150_chgr_minimal
EOF
    chmod 755 /etc/local.d/pm6150_charger.start
    rc-update add local default 2>/dev/null || true

    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/pm6150-charger.conf <<'EOF'
options pm6150_chgr_minimal icl_ma=1800 fcc_ma=2000
EOF
}

load_modules_now() {
    log "loading modules (read-only probe first)"
    modprobe -r pm6150_chgr_minimal joyeuse_battery_shim 2>/dev/null || true
    modprobe -r qcom_qg 2>/dev/null || true
    modprobe qcom_qg
    modprobe joyeuse_battery_shim
    modprobe pm6150_chgr_minimal enable_writes=0 2>/dev/null || true
    modprobe -r pm6150_chgr_minimal 2>/dev/null || true
    modprobe pm6150_chgr_minimal
}

install_pd_dtb() {
    model="$(tr -d '\0' < /sys/firmware/devicetree/base/model)"
    case "${model}" in
        *Tianma*) dtb_name=sm7125-xiaomi-joyeuse-tianma-pd.dtb ;;
        *Huaxing*) dtb_name=sm7125-xiaomi-joyeuse-huaxing-pd.dtb ;;
        *) log "unknown panel in model='${model}', defaulting to tianma-pd"; dtb_name=sm7125-xiaomi-joyeuse-tianma-pd.dtb ;;
    esac
    src="${CHGR_REPO}/dtb/${dtb_name}"
    if [ ! -f "${src}" ]; then
        log "PD DTB not found at ${src}; skip --with-pd-dtb"
        return 1
    fi
    mkdir -p /boot/dtbs/qcom
    install -m644 "${src}" "/boot/dtbs/qcom/${dtb_name}"
    cp -a /etc/deviceinfo "/etc/deviceinfo.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    if ! grep -q '^deviceinfo_dtb=' /etc/deviceinfo 2>/dev/null; then
        printf '\ndeviceinfo_dtb="qcom/%s"\n' "${dtb_name%.dtb}" >> /etc/deviceinfo
    else
        sed -i "s|^deviceinfo_dtb=.*|deviceinfo_dtb=\"qcom/${dtb_name%.dtb}\"|" /etc/deviceinfo
    fi
    mkinitfs
    log "PD DTB installed (${dtb_name}). Reboot required."
}

show_status() {
    log "=== status ==="
    echo "kernel: ${KREL}"
    ls -la "/lib/modules/${KREL}/extra/" 2>/dev/null || true
    for f in /sys/class/power_supply/battery/status \
             /sys/class/power_supply/qcom_qg/capacity \
             /sys/class/power_supply/qcom_qg/current_now \
             /sys/class/power_supply/qcom_qg/scope; do
        if [ -f "${f}" ]; then
            printf '%s: %s\n' "${f}" "$(cat "${f}")"
        fi
    done
    if [ -f /sys/class/power_supply/tcpm-source-psy-c440000.spmi:pmic@0:typec@1500/online ]; then
        printf 'usb_online: %s\n' "$(cat /sys/class/power_supply/tcpm-source-psy-c440000.spmi:pmic@0:typec@1500/online)"
    fi
    if [ -f /sys/class/typec/port0/power_role ]; then
        printf 'power_role: %s\n' "$(cat /sys/class/typec/port0/power_role)"
    fi
    dmesg | grep -i pm6150_chgr | tail -5 || true
}

main() {
    need_root "$@"
    [ "${KREL}" = "6.12.1-sm7125" ] || {
        log "unexpected kernel ${KREL}; script tested for 6.12.1-sm7125"
        exit 1
    }
    backup_ha
    install_deps
    clone_sources
    prepare_kernel_tree
    build_modules
    install_modules
    install_openrc_hook
    load_modules_now
    [ "${WITH_PD_DTB}" -eq 1 ] && install_pd_dtb || log "skip PD DTB (pass --with-pd-dtb to enable)"
    show_status
    log "done. Plug charger/hub and check battery/status. PD DTB needs reboot if installed."
}

main "$@"
