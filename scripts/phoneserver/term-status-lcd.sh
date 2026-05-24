#!/bin/sh
# Status layout for the phone LCD (colors + fewer lines). Not for SSH pipes.
# Invoked by phone-display-loop.sh only.

set -eu

# Linux console ANSI (16 colors)
R='\033[0m'
B='\033[1m'
D='\033[40m'       # black background for whole frame
T='\033[1;36m'     # title
L='\033[90m'       # labels (bright black / grey)
V='\033[97m'       # values
G='\033[1;32m'
Y='\033[1;33m'
M='\033[1;35m'
C='\033[1;34m'

hostname=$(hostname)
load=$(cut -d' ' -f1-3 /proc/loadavg)
mem=$(free -h | awk '/^Mem:/ {printf "%s / %s", $3, $2}')
disk=$(df -h / | awk 'NR==2 {printf "%s / %s", $3, $2}')
uptime_s=$(uptime | sed 's/^.* up /up /' | cut -d, -f1)
bat_cap=""
bat_stat=""
if [ -r /sys/class/power_supply/qcom_qg/capacity ]; then
    bat_cap=$(cat /sys/class/power_supply/qcom_qg/capacity)
    bat_stat=$(cat /sys/class/power_supply/qcom_qg/status 2>/dev/null || echo "?")
fi
wlan_ip=$(ip -4 -o addr show wlan0 2>/dev/null | awk '{print $4}' | head -1)
temp=""
for tz in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$tz" ] || continue
    t=$(cat "$tz" 2>/dev/null)
    [ -n "$t" ] || continue
    temp=$((t / 1000))
    break
done
beszel=stopped
if pgrep -x beszel-agent >/dev/null 2>&1; then
    beszel=ok
fi

bat_color="$G"
case "$bat_stat" in
    Discharging) bat_color="$Y" ;;
    Charging) bat_color="$C" ;;
esac

printf '%b' "${D}"
printf '\n %bphoneserver%b\n' "$T" "$R"
printf ' %b%s%b\n\n' "$L" "$(date '+%H:%M:%S  %d.%m.%Y')" "$R"

printf ' %bload%b    %b%s%b\n' "$L" "$R" "$V" "$load" "$R"
printf ' %bmem%b     %b%s%b\n' "$L" "$R" "$V" "$mem" "$R"
printf ' %bdisk%b    %b%s%b\n' "$L" "$R" "$V" "$disk" "$R"
printf ' %buptime%b  %b%s%b\n' "$L" "$R" "$V" "$uptime_s" "$R"

[ -n "$bat_cap" ] && printf ' %bbattery%b %b%s%%%b %b(%s)%b\n' \
    "$L" "$R" "$bat_color" "$bat_cap" "$R" "$bat_color" "$bat_stat" "$R"
[ -n "$temp" ] && printf ' %btemp%b    %b%s C%b\n' "$L" "$R" "$Y" "$temp" "$R"

printf '\n'
printf ' %bwlan%b     %b%s%b\n' "$L" "$R" "$V" "${wlan_ip:-down}" "$R"
if [ "$beszel" = ok ]; then
    printf ' %bbeszel%b   %bonline%b\n' "$L" "$R" "$G" "$R"
else
    printf ' %bbeszel%b   %boffline%b\n' "$L" "$R" "$Y" "$R"
fi
printf '%b' "$R"
