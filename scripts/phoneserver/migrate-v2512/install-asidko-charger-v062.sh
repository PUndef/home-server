#!/bin/sh
# Install asidko pm6150-charger-mainline v0.6.2 prebuilt modules + PD DTB (6.14.7-sm7125).
# For postmarketOS v25.12 / fastboot-bootpart scheme (systemd).
#
# Usage on phoneserver: sudo sh install-asidko-charger-v062.sh

set -eu

RELEASE=v0.6.2
BASE="https://github.com/asidko/pm6150-charger-mainline/releases/download/${RELEASE}"
KREL="$(uname -r)"
WORKDIR="${TMPDIR:-/tmp}/asidko-chgr-${RELEASE}"
PANEL="tianma"

log() { printf '[asidko-chgr] %s\n' "$*"; }

need_root() {
    [ "$(id -u)" -eq 0 ] || exec sudo "$0" "$@"
}

detect_panel() {
    model="$(tr -d '\0' < /sys/firmware/devicetree/base/model 2>/dev/null || true)"
    case "$model" in
        *Huaxing*) PANEL=huaxing ;;
        *Tianma*)  PANEL=tianma ;;
        *) log "unknown panel in model='$model', default tianma" ;;
    esac
}

case "$KREL" in
    6.14.*-sm7125) ;;
    *)
        log "WARN: kernel $KREL — prebuilt .ko target 6.14.7-sm7125"
        ;;
esac

need_root
detect_panel
DTB_NAME="sm7125-xiaomi-joyeuse-${PANEL}-pd.dtb"
DTB_PATH="qcom/${DTB_NAME%.dtb}"

mkdir -p "$WORKDIR"
for f in joyeuse_battery_shim.ko pm6150_chgr_minimal.ko qcom_qg.ko.patched "$DTB_NAME"; do
    log "download $f"
    curl -fL -o "${WORKDIR}/${f}" "${BASE}/${f}"
done

install -d "/lib/modules/${KREL}/extra"
install -d "/lib/modules/${KREL}/kernel/drivers/power/supply"
install -m644 "${WORKDIR}/joyeuse_battery_shim.ko" "/lib/modules/${KREL}/extra/"
install -m644 "${WORKDIR}/pm6150_chgr_minimal.ko" "/lib/modules/${KREL}/extra/"
install -m644 "${WORKDIR}/qcom_qg.ko.patched" \
    "/lib/modules/${KREL}/kernel/drivers/power/supply/qcom_qg.ko"
depmod -a

modprobe -r pm6150_chgr_minimal joyeuse_battery_shim 2>/dev/null || true
modprobe -r qcom_qg 2>/dev/null || true
modprobe qcom_qg
modprobe joyeuse_battery_shim
modprobe pm6150_chgr_minimal

printf '%s\n' joyeuse_battery_shim > /etc/modules-load.d/joyeuse-battery.conf
printf '%s\n' pm6150_chgr_minimal > /etc/modules-load.d/pm6150-charger.conf
printf '%s\n' 'options pm6150_chgr_minimal icl_ma=1800 fcc_ma=2000 term_capacity=80 term_hysteresis=5' \
    > /etc/modprobe.d/pm6150-charger.conf

# systemd late-load (qcom_qg probe race)
if [ -d /etc/systemd/system ]; then
    cat > /etc/systemd/system/pm6150-chgr-late.service <<'UNIT'
[Unit]
Description=Load pm6150_chgr_minimal after qcom_qg
After=systemd-modules-load.service
ConditionPathExists=/sys/class/power_supply/qcom_qg

[Service]
Type=oneshot
ExecStart=/sbin/modprobe joyeuse_battery_shim
ExecStart=/sbin/modprobe pm6150_chgr_minimal
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable pm6150-chgr-late.service
fi

install -d /boot/dtbs/qcom
install -m644 "${WORKDIR}/${DTB_NAME}" "/boot/dtbs/qcom/${DTB_NAME}"

if [ -f /etc/deviceinfo ]; then
    cp -a /etc/deviceinfo /etc/deviceinfo.bak."$(date +%Y%m%d)"
    if grep -q '^deviceinfo_dtb=' /etc/deviceinfo; then
        sed -i "s|^deviceinfo_dtb=.*|deviceinfo_dtb=\"${DTB_PATH}\"|" /etc/deviceinfo
    else
        printf '\ndeviceinfo_dtb="%s"\n' "$DTB_PATH" >> /etc/deviceinfo
    fi
    mkinitfs
    log "PD DTB via deviceinfo_dtb=$DTB_PATH — reboot required"
else
    log "WARN: no /etc/deviceinfo — PD DTB installed but not wired into boot"
fi

log "done. After reboot verify:"
log "  cat /sys/firmware/devicetree/base/soc@0/spmi@c440000/pmic@0/typec@1500/connector/power-role"
log "  cat /sys/class/power_supply/battery/status"
