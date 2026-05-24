#!/bin/sh
set -e
echo "=== DRM/FB ==="
ls -la /dev/dri/ 2>/dev/null || echo "no dri"
ls -la /dev/fb* 2>/dev/null || echo "no fb"
echo "=== graphics ==="
ls /sys/class/graphics/ 2>/dev/null || true
echo "=== VT active ==="
cat /sys/class/tty/console/active 2>/dev/null || true
echo "=== cmdline ==="
cat /proc/cmdline
echo "=== kmscon pkg ==="
apk info -e kmscon 2>/dev/null || apk search -e kmscon 2>/dev/null | head -3
echo "=== agetty ==="
ps | grep -E 'agetty|kmscon|fbcon' | grep -v grep || true
echo "=== backlight ==="
ls /sys/class/backlight/ 2>/dev/null || true
