#!/bin/bash
# Quick check after v25.06 reinstall: kernel version, network interfaces,
# whether wlan0 came up and ath10k_snoc managed to load firmware.
PHONE_IP=${PHONE_IP:-172.16.42.1}

sshpass -p changemenow ssh \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "pmos@${PHONE_IP}" \
    'echo === kernel ===
uname -r
echo === hostname / uptime ===
hostname; uptime
echo
echo === net interfaces ===
ls /sys/class/net/
echo
echo === iw dev ===
iw dev 2>&1 || true
echo
echo === ath10k/wlan/regulatory dmesg ===
echo changemenow | sudo -S dmesg 2>/dev/null | grep -iE "ath10k|wlan|wcn|regul|cfg80211|qcom_q6" | tail -30'
