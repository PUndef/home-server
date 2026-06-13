#!/bin/sh
# Post-flash smoke test BEFORE restoring Home Assistant.
# Run on phoneserver as root, or: ssh pmos@IP sudo sh smoke-test-post-flash.sh
#
# Exit 0 = all critical checks passed → safe to restore HA.
# Exit 1 = something failed → fix before HA.

set -eu

FAIL=0
warn() { printf '[smoke] WARN: %s\n' "$*"; }
fail() { printf '[smoke] FAIL: %s\n' "$*"; FAIL=1; }
ok()   { printf '[smoke] OK: %s\n' "$*"; }

check() {
    desc="$1"
    shift
    if "$@"; then
        ok "$desc"
    else
        fail "$desc"
    fi
}

KREL="$(uname -r)"
case "$KREL" in
    6.14.*-sm7125) ok "kernel $KREL (expected 6.14.x-sm7125)" ;;
    *) warn "kernel $KREL — expected 6.14.x-sm7125 for asidko charger binaries" ;;
esac

[ "$(hostname)" = "phoneserver" ] && ok "hostname phoneserver" || warn "hostname is $(hostname), expected phoneserver"

# --- network: at least one uplink must work ---
HAS_UPLINK=0
if ip -4 addr show eth0 2>/dev/null | grep -q 'inet '; then
    ok "eth0 has IPv4"
    HAS_UPLINK=1
else
    warn "eth0 has no IPv4 (hub/LAN not up — OK if Wi-Fi works)"
fi

if ip -4 addr show wlan0 2>/dev/null | grep -q 'inet '; then
    ok "wlan0 has IPv4"
    HAS_UPLINK=1
else
    warn "wlan0 has no IPv4"
fi

[ "$HAS_UPLINK" -eq 1 ] || fail "no IPv4 on eth0 or wlan0"

check "ping 1.1.1.1" ping -c1 -W3 1.1.1.1 >/dev/null 2>&1
check "DNS resolve" ping -c1 -W3 dl-cdn.alpinelinux.org >/dev/null 2>&1

# --- charger stack (asidko) ---
for m in qcom_qg joyeuse_battery_shim pm6150_chgr_minimal; do
    lsmod | grep -q "^${m} " && ok "module $m loaded" || fail "module $m not loaded"
done

if [ -f /sys/class/power_supply/qcom_qg/scope ]; then
    scope="$(cat /sys/class/power_supply/qcom_qg/scope)"
    [ "$scope" = "Device" ] && ok "qcom_qg scope=Device" || fail "qcom_qg scope=$scope (want Device)"
fi

if [ -f /sys/firmware/devicetree/base/soc@0/spmi@c440000/pmic@0/typec@1500/connector/power-role ]; then
    role="$(tr -d '\0' < /sys/firmware/devicetree/base/soc@0/spmi@c440000/pmic@0/typec@1500/connector/power-role)"
    [ "$role" = "dual" ] && ok "Type-C power-role=dual (PD DTB)" || warn "Type-C power-role=$role (want dual for hub PD)"
fi

if [ -f /sys/class/power_supply/battery/status ]; then
    printf '[smoke] battery/status: %s\n' "$(cat /sys/class/power_supply/battery/status)"
fi
if [ -f /sys/class/typec/port0/power_role ]; then
    printf '[smoke] power_role: %s\n' "$(cat /sys/class/typec/port0/power_role)"
fi

# eth0 must survive if hub is connected (critical for srv segment)
if ip link show eth0 >/dev/null 2>&1; then
    check "eth0 interface exists" true
    # if hub connected, carrier should be up
    if grep -q 'LOWER_UP' /sys/class/net/eth0/operstate 2>/dev/null || \
       ip link show eth0 | grep -q 'LOWER_UP'; then
        ok "eth0 link up"
    else
        warn "eth0 exists but link down (hub unplugged?)"
    fi
fi

# --- services (no HA yet) ---
service_up() {
    svc="$1"
    if rc-service "$svc" status >/dev/null 2>&1; then
        return 0
    fi
    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$svc" 2>/dev/null; then
        return 0
    fi
    return 1
}

check "sshd running" service_up sshd || pgrep -x sshd.pam >/dev/null 2>&1
check "chronyd running" service_up chronyd
if command -v docker >/dev/null 2>&1; then
    check "docker running" service_up docker
else
    warn "docker not installed yet (OK before HA restore script)"
fi

# HA must NOT be running yet (pre-restore)
if service_up homeassistant 2>/dev/null; then
    warn "homeassistant service already running (restore may have happened?)"
else
    ok "homeassistant not running (expected before restore)"
fi

# --- disk ---
avail_g="$(df -BG / | awk 'NR==2 {print $4}' | tr -d G)"
[ "${avail_g:-0}" -gt 50 ] && ok "root free ${avail_g}G" || warn "root free only ${avail_g}G"

echo
if [ "$FAIL" -eq 0 ]; then
    printf '[smoke] PASS — safe to restore HA\n'
    exit 0
fi
printf '[smoke] FAIL — fix issues before HA restore\n'
exit 1
