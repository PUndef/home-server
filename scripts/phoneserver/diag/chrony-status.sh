#!/bin/bash
PHONE_IP=${PHONE_IP:-192.168.1.116}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'echo === chronyc sources ===
sudo chronyc sources
echo
echo === chronyc tracking ===
sudo chronyc tracking
echo
echo === sleep + force step ===
sleep 5
sudo chronyc -a makestep
sleep 3
date
echo
echo === /etc/chrony.conf or /etc/chrony/chrony.conf ===
sudo cat /etc/chrony/chrony.conf 2>/dev/null || sudo cat /etc/chrony.conf 2>/dev/null'
