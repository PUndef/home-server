#!/bin/sh
# Activate srv (192.168.50.0/24) interface after ASUS is removed
# and OpenWrt becomes the main router (provider WAN goes directly into X3000T).
#
# Usage on router (after physical re-cabling, ASUS powered off):
#     sh /root/migration-activate-srv.sh
#
# Source of truth: router-openwrt-x3000t.md / migration-asus-to-openwrt.md

set -e

echo '=== 1. Verify WAN got a real public IP (not 192.168.50.x from ASUS) ==='
WAN_IP="$(ifstatus wan | jsonfilter -e '@["ipv4-address"][0].address' 2>/dev/null)"
echo "WAN ipv4 = ${WAN_IP:-<none>}"
case "$WAN_IP" in
    192.168.50.*|"")
        echo "ABORT: WAN still in 192.168.50.0/24 or empty. Check provider cable / DHCP."
        exit 1
        ;;
esac

echo '=== 2. Enable srv interface ==='
uci -q delete network.srv.disabled
uci commit network
ifup srv
sleep 2

echo '=== 3. Restart firewall (so srv zone activates with the live link) ==='
/etc/init.d/firewall restart
sleep 1

echo '=== 4. Force DDNS update (immediate, do not wait for 10min cycle) ==='
killall -q dynamic_dns_updater.sh 2>/dev/null || true
/etc/init.d/ddns restart
sleep 3

echo '=== 5. Restart VPN stack so awg1/awg2/podkop re-evaluate routes via the new WAN ==='
/etc/init.d/sing-box restart 2>/dev/null || true
/etc/init.d/podkop restart 2>/dev/null || true
/etc/init.d/zapret restart 2>/dev/null || true
sleep 2
sh /opt/zapret/custom.bypass_devices.sh
/etc/init.d/pbr restart

echo '=== 6. Re-pin GitHub routes via awg1 (community lists updates) ==='
ip route replace 185.199.108.0/22 dev awg1 2>/dev/null || true
ip route replace 140.82.112.0/20 dev awg1 2>/dev/null || true

echo '=== 7. Status ==='
echo '--- WAN ---'
ifstatus wan | jsonfilter -e '@["ipv4-address"][0]'
echo '--- srv ---'
ip -br a show dev lan2
ip -4 route show dev lan2
echo '--- DDNS ---'
cat /var/run/ddns/cloud_pundef.ip 2>/dev/null
echo
echo '--- Firewall zones ---'
nft list chains inet fw4 | grep -E 'input_(lan|srv|wan)|forward_(lan|srv|wan)'
echo
echo 'DONE. Now run check_stack.py from the PC.'
