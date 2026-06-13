#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../phone-defaults.sh
source "${SCRIPT_DIR}/../phone-defaults.sh"

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "${SSH_REMOTE}" \
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
