#!/bin/sh
# Colored status on phone LCD. Backlight turns off after LCD_IDLE_SEC (see conf.d).
CONSOLE=/dev/tty1
STATUS=/opt/phoneserver/term-status-lcd.sh
INTERVAL="${INTERVAL:-3}"
LCD_IDLE_SEC="${LCD_IDLE_SEC:-30}"
BL=/sys/class/backlight/backlight
BL_ON="${BL_ON:-4000}"
BL_OFF="${BL_OFF:-0}"
FONT="${LCD_FONT:-ter-v32n}"

console_ready=0
idle=0

bl_set() {
    [ -w "$BL/brightness" ] || return 0
    echo "$1" > "$BL/brightness"
}

bl_off() {
    bl_set "$BL_OFF"
}

bl_on() {
    bl_set "$BL_ON"
}

# Кнопка питания / ручная яркость — сброс таймера
maybe_wake() {
    [ -r "$BL/brightness" ] || return 0
    cur=$(cat "$BL/brightness" 2>/dev/null) || return 0
    [ "$cur" -gt 200 ] 2>/dev/null || return 0
    if [ "$idle" -ge "$LCD_IDLE_SEC" ]; then
        idle=0
    fi
}

setup_console() {
    echo 1 > /sys/class/vtconsole/vtcon1/bind 2>/dev/null || true
    chvt 1 2>/dev/null || true
    if [ "$console_ready" -eq 0 ] && command -v setfont >/dev/null 2>&1; then
        setfont "$FONT" 2>/dev/null \
            || setfont ter-v28n 2>/dev/null \
            || setfont ter-v24n 2>/dev/null \
            || true
        console_ready=1
    fi
    if command -v setterm >/dev/null 2>&1; then
        setterm -blank "$LCD_IDLE_SEC" -powerdown "$LCD_IDLE_SEC" -powersave off \
            </dev/null >"$CONSOLE" 2>/dev/null || true
    fi
}

draw_status() {
    printf '\033[2J\033[H' > "$CONSOLE"
    if [ -x "$STATUS" ]; then
        sh "$STATUS" > "$CONSOLE"
    else
        printf '\033[40m\033[97m  phoneserver\n  missing %s\n\033[0m' "$STATUS" > "$CONSOLE"
    fi
}

while true; do
    maybe_wake

    if [ "$idle" -lt "$LCD_IDLE_SEC" ]; then
        setup_console
        bl_on
        draw_status 2>/dev/null
        idle=$((idle + INTERVAL))
    else
        bl_off
    fi

    sleep "$INTERVAL"
done
