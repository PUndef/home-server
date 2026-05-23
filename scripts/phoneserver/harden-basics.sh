#!/bin/bash
# One-off hardening / housekeeping for a freshly-installed phoneserver:
#   - install and enable chrony for NTP (RTC battery missing, clock resets
#     to 1975 on every reboot)
#   - change the placeholder `pmos` password from changemenow to NEW_PASS
#   - disable SSH password auth (key-only login from now on)
#
# After this script:
#   - update SUDO_PASS in your env or in scripts to the new password
#   - SSH only works via ~/.ssh/phoneserver_nopass

set -e

PHONE_IP=${PHONE_IP:-172.16.42.1}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
OLD_PASS=${OLD_PASS:-changemenow}
NEW_PASS=${NEW_PASS:?NEW_PASS env var must be set}

ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    "set -e
    echo '=== 1) install chrony ==='
    echo '$OLD_PASS' | sudo -S apk add chrony chrony-openrc 2>&1 | tail -5

    echo '=== 2) enable chrony in default runlevel ==='
    echo '$OLD_PASS' | sudo -S rc-update add chronyd default 2>&1 | tail -3
    echo '$OLD_PASS' | sudo -S rc-service chronyd start 2>&1 | tail -3
    sleep 2

    echo '=== 3) sync now (one-shot) and show clock ==='
    echo '$OLD_PASS' | sudo -S chronyc -a makestep 2>&1 | tail -3
    date

    echo '=== 4) change pmos password ==='
    echo '$OLD_PASS' | sudo -S sh -c \"
        printf '%s\n%s\n' '$NEW_PASS' '$NEW_PASS' | passwd pmos
    \"

    echo '=== 5) disable SSH password auth ==='
    echo '$NEW_PASS' | sudo -S sh -c '
        sed -i \"s/^#\\?PasswordAuthentication.*/PasswordAuthentication no/\" /etc/ssh/sshd_config
        sed -i \"s/^#\\?ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/\" /etc/ssh/sshd_config
        grep -E \"^PasswordAuthentication|^ChallengeResponseAuthentication\" /etc/ssh/sshd_config
        rc-service sshd reload
    '

    echo '=== 6) verify ==='
    rc-status default 2>&1 | grep -E \"chronyd|sshd\"
    chronyc tracking 2>&1 | head -10 || true"
