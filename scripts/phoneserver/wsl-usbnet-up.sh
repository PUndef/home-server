#!/bin/bash
# Bring up the CDC-NCM USB-network interface to phoneserver after a reboot of
# the phone or a fresh `usbipd attach`.
#
# Phone side runs pmOS gadget at 172.16.42.1/16 on usb0. We give the WSL side
# 172.16.42.2/24 statically (pmOS does not run a DHCP server on usb0).
#
# Prereqs:
#   - phone is attached via `usbipd attach --wsl --busid <id>` (run on Windows
#     as administrator)
#   - ~/.ssh/phoneserver_nopass already exists (see setup-ssh-key.sh)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/phone-defaults.sh"
WSL_USB_IP=${WSL_USB_IP:-172.16.42.2/24}

IFACE=$(ip -4 link show | grep -oP 'enx[a-f0-9]+' | head -1)
if [ -z "$IFACE" ]; then
    echo "ERROR: no USB-cdc interface in WSL. Run usbipd attach in PowerShell first."
    exit 1
fi
echo "USB iface in WSL: $IFACE"

sudo ip addr flush dev "$IFACE" 2>/dev/null || true
sudo ip addr add "$WSL_USB_IP" dev "$IFACE"
sudo ip link set "$IFACE" up

echo "=== wait for phone ssh ==="
for i in $(seq 1 30); do
    if ssh -o StrictHostKeyChecking=no \
           -o UserKnownHostsFile=/dev/null \
           -o ConnectTimeout=2 \
           -i "$SSH_KEY" \
           "${SSH_REMOTE}" 'true' 2>/dev/null; then
        echo "phone responds (try $i)"
        break
    fi
    sleep 2
done

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "${SSH_REMOTE}" \
    'hostname; uname -r; uptime'
