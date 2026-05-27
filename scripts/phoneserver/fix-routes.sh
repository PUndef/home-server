#!/bin/bash
# Remove the stale default route via the WSL USB-net link so the phone uses
# the wlan0 default via the LAN gateway. Also drop the duplicate secondary
# IP added by a stray dhcpcd request, and lock /etc/resolv.conf with .head.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo "=== routes before ==="
ip route
echo
echo "=== fixes ==="
# kill default via USB (WSL gadget / link-local)
sudo ip route del default via 172.16.42.2 dev usb0 2>&1 || true
sudo ip route del default dev usb0 scope link 2>&1 || true
# drop stale secondary address if present
sudo ip addr del 192.168.1.117/24 dev wlan0 2>&1 || true
# ensure wlan0 default exists after USB cleanup
if ! ip route show default | grep -q "dev wlan0"; then
    sudo rc-service dhcpcd restart 2>&1 || sudo ip route add default via 192.168.1.1 dev wlan0 metric 3004
fi
echo
echo "=== routes after ==="
ip route
echo
echo "=== resolv ==="
sudo sh -c "printf '\''nameserver 1.1.1.1\nnameserver 8.8.8.8\n'\'' > /etc/resolv.conf"
cat /etc/resolv.conf
echo
echo "=== ping ==="
ping -c 3 -W 2 1.1.1.1 | tail -4'
