#!/bin/sh
# Free dwc3 UDC for USB host (hub ethernet). pmOS initramfs enables g1 gadget on usb0.
for g in /sys/kernel/config/usb_gadget/*; do
    [ -f "$g/UDC" ] || continue
    echo '' >"$g/UDC" 2>/dev/null || true
done
ip link set usb0 down 2>/dev/null || true
