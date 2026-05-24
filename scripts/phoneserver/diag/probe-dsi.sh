#!/bin/sh
for f in status enabled dpms power modes; do
    p="/sys/class/drm/card0-DSI-1/$f"
    if [ -e "$p" ]; then
        printf '%s: ' "$f"
        sudo cat "$p" 2>&1
    fi
done
