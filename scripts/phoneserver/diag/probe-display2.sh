#!/bin/sh
apk search kmscon 2>/dev/null || echo "no kmscon"
ls /sys/class/vtconsole/ 2>/dev/null || true
cat /sys/class/vtconsole/vtcon0/name 2>/dev/null || true
cat /sys/class/vtconsole/vtcon1/name 2>/dev/null || true
busybox openvt 2>&1 | head -1
