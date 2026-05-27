#!/bin/bash
# Connect wlan0 on phoneserver to a WPA2 network. Generates
# /etc/wpa_supplicant/wpa_supplicant.conf via wpa_passphrase and starts
# wpa_supplicant + dhcpcd on wlan0.
#
# Pass SSID and PSK via env or args:
#   WIFI_SSID=DECO_HOME WIFI_PSK="...." ./wifi-connect.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=usb source "${SCRIPT_DIR}/../phone-defaults.sh"
WIFI_SSID=${WIFI_SSID:?WIFI_SSID env var required}
WIFI_PSK=${WIFI_PSK:?WIFI_PSK env var required}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "sudo sh -c \"
        # generate wpa_supplicant.conf
        printf 'ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=wheel\nupdate_config=1\ncountry=EU\n' > /etc/wpa_supplicant/wpa_supplicant.conf
        wpa_passphrase '$WIFI_SSID' '$WIFI_PSK' >> /etc/wpa_supplicant/wpa_supplicant.conf
        chmod 600 /etc/wpa_supplicant/wpa_supplicant.conf
        # also make per-interface symlink (openrc init script looks for it)
        ln -sf wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
        # restart any prior wpa_supplicant instance for wlan0
        killall wpa_supplicant 2>/dev/null || true
        sleep 1
        # start
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -D nl80211
        sleep 3
        # DHCP
        killall dhcpcd 2>/dev/null || true
        sleep 1
        dhcpcd -t 30 -L wlan0 2>&1 | tail -10
        sleep 2
        echo '=== wlan0 addr ==='
        ip -4 addr show wlan0
        echo '=== route ==='
        ip route
        echo '=== ping via wlan0 ==='
        ping -c 3 -W 2 -I wlan0 1.1.1.1 2>&1 | tail -5
        # ensure persistent
        rc-update add wpa_supplicant default 2>&1 || true
        rc-update add dhcpcd default 2>&1 || true
    \""
