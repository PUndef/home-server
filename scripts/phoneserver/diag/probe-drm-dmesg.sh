#!/bin/sh
dmesg 2>/dev/null | grep -iE 'drm|dsi|fbcon|panel|display|msm' | tail -40
