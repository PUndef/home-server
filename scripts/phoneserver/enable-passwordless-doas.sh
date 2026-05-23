#!/bin/bash
# v25.06 of pmOS ships doas + doas-sudo-shim instead of real sudo, which
# makes our `echo $PASS | sudo -S ...` pattern in helpers break. Replace
# doas-sudo-shim with real sudo and add pmos to wheel-style sudoers entry
# with NOPASSWD (matches the operational model of proxmox_pundef_nopass).
#
# Uses `expect` because the initial doas in pmOS needs a TTY.

set -e

PHONE_IP=${PHONE_IP:-172.16.42.1}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}
PMOS_PASS=${PMOS_PASS:-changemenow}

# Combined one-shot: set up default route + DNS, replace doas-sudo-shim
# with real sudo, drop NOPASSWD entry. doas-on-tty for password prompts.
expect <<EOF
set timeout 180
log_user 1
spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" -t "pmos@${PHONE_IP}" \
    "doas sh -c '
        echo === route ===
        ip route del default 2>/dev/null || true
        ip route add default via 172.16.42.2
        printf \"nameserver 1.1.1.1\nnameserver 8.8.8.8\n\" > /etc/resolv.conf
        echo === apk update ===
        apk update 2>&1 | tail -3
        echo === install sudo ===
        apk add sudo 2>&1 | tail -3
        echo === remove doas-sudo-shim ===
        apk del doas-sudo-shim 2>&1 | tail -3
        echo === sudoers ===
        mkdir -p /etc/sudoers.d
        echo \"pmos ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/pmos-nopasswd
        chmod 0440 /etc/sudoers.d/pmos-nopasswd
        cat /etc/sudoers.d/pmos-nopasswd
    '"
expect {
    -re {[Pp]assword: ?}    { send -- "$PMOS_PASS\r"; exp_continue }
    eof
}
EOF

echo
echo "=== verify (sudo passwordless) ==="
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
    -i "$SSH_KEY" "pmos@${PHONE_IP}" \
    'sudo whoami; sudo -n echo "passwordless OK"'
