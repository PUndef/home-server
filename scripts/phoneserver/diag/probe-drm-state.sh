#!/bin/sh
find /sys/class/drm -name status -exec sh -c 'echo "{}: $(cat {})"' \; 2>/dev/null
find /sys/class/drm -name enabled -exec sh -c 'echo "{}: $(cat {})"' \; 2>/dev/null
ls /sys/class/leds/ 2>/dev/null | head -20
