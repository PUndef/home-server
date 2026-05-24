#!/bin/sh
# One-screen phoneserver status for SSH / local console (no curses).
# Run on the phone: ./term-status.sh
# From WSL: PHONE_IP=192.168.1.116 ./scripts/phoneserver/term-status.sh remote

set -eu

if [ "${1:-}" = "remote" ]; then
    PHONE_IP="${PHONE_IP:-192.168.1.116}"
    SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
    exec ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}" "pmos@${PHONE_IP}" \
        "sh -s" < "$(dirname "$0")/term-status.sh"
fi

hr() { printf '%s\n' '----------------------------------------'; }

hostname=$(hostname)
kernel=$(uname -r)
uptime_s=$(uptime | sed 's/^.* up /up /')
load=$(cut -d' ' -f1-3 /proc/loadavg)
mem=$(free -h | awk '/^Mem:/ {printf "%s used / %s total (%s free)", $3,$2,$4}')
disk=$(df -h / | awk 'NR==2 {printf "%s used / %s total (%s avail)", $3,$2,$4}')
bat_cap=""
bat_stat=""
if [ -r /sys/class/power_supply/qcom_qg/capacity ]; then
    bat_cap=$(cat /sys/class/power_supply/qcom_qg/capacity)
    bat_stat=$(cat /sys/class/power_supply/qcom_qg/status 2>/dev/null || echo "?")
fi
wlan_ip=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | paste -sd ', ' - || true)
usb_ip=$(ip -4 -o addr show usb0 2>/dev/null | awk '{print $4}' | paste -sd ', ' - || true)
if pgrep -x beszel-agent >/dev/null 2>&1; then
    beszel="running (pid $(pgrep -x beszel-agent | head -1))"
else
    beszel=stopped
fi
temp=""
for tz in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$tz" ] || continue
    t=$(cat "$tz" 2>/dev/null)
    [ -n "$t" ] || continue
    temp=$((t / 1000))
    break
done

printf '\n  phoneserver — %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || date)"
hr
printf '  host      %s (%s)\n' "$hostname" "$kernel"
printf '  uptime    %s\n' "$uptime_s"
printf '  load      %s\n' "$load"
hr
printf '  memory    %s\n' "$mem"
printf '  disk /    %s\n' "$disk"
[ -n "$bat_cap" ] && printf '  battery   %s%% (%s)\n' "$bat_cap" "$bat_stat"
[ -n "$temp" ] && printf '  temp      %s C\n' "$temp"
hr
printf '  wlan0     %s\n' "${wlan_ip:-down}"
printf '  usb0      %s\n' "${usb_ip:-down}"
printf '  beszel    %s\n' "$beszel"
hr
printf '  loop: watch-status.sh\n\n'
