#!/bin/sh
printf 'consoleblank=%s\n' "$(cat /sys/module/kernel/parameters/consoleblank 2>/dev/null)"
printf 'dpms=%s\n' "$(cat /sys/class/drm/card0-DSI-1/dpms 2>/dev/null)"
printf 'bl_power=%s brightness=%s\n' \
    "$(cat /sys/class/backlight/backlight/bl_power 2>/dev/null)" \
    "$(cat /sys/class/backlight/backlight/brightness 2>/dev/null)"
if [ -r /sys/class/backlight/backlight/brightness_max ]; then
    printf 'brightness_max=%s\n' "$(cat /sys/class/backlight/backlight/brightness_max)"
fi
# kernel default when module loads: often 600 if not set in cmdline
grep -E 'consoleblank|quiet' /proc/cmdline
