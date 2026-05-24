#!/bin/sh
find /sys/class/drm -type f -name status 2>/dev/null
find /sys/class/drm -maxdepth 3 -type d 2>/dev/null | head -30
