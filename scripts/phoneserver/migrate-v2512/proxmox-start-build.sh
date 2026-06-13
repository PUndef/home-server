#!/bin/bash
# Run ON Proxmox as root to patch pmbootstrap and start headless build.
set -euo pipefail

sed -i 's/\r$//' /root/pmos-build/migrate-v2512/*.sh

PYFILE="$(python3 -c 'import pmb.install._install as i, os; print(os.path.dirname(i.__file__))')/_install.py"
if ! grep -q 'patched for joyeuse' "$PYFILE"; then
    sed -i 's|if int(config.boot_size) >= int(default):|if True:  # patched for joyeuse 384MB cache|' "$PYFILE"
fi
echo "patched $PYFILE"

need_init=0
if [ ! -f /root/.local/var/pmbootstrap/version ]; then
    need_init=1
fi
if [ ! -d /root/.local/var/pmbootstrap/chroot_native ]; then
    need_init=1
fi

if [ "$need_init" -eq 1 ]; then
    echo "wiping incomplete pmbootstrap work dir and running init..."
    pmbootstrap --as-root shutdown 2>/dev/null || true
    rm -rf /root/.local/var/pmbootstrap
    export PMB_AS_ROOT=1
    expect /root/pmos-build/migrate-v2512/pmbootstrap-init-v2512.exp \
        > /root/pmos-build/init.log 2>&1 || {
        echo "init failed — see /root/pmos-build/init.log"
        tail -40 /root/pmos-build/init.log
        exit 1
    }
    # Re-apply boot_size after init (default may be 512)
    pmbootstrap --as-root config boot_size 256
    pmbootstrap --as-root config ui none
    pmbootstrap --as-root config hostname phoneserver
    pmbootstrap --as-root config user pmos
fi

pkill -f 'build-headless.sh' 2>/dev/null || true
nohup bash /root/pmos-build/migrate-v2512/build-headless.sh > /root/pmos-build/build.log 2>&1 &
echo "build pid=$!"
sleep 5
tail -30 /root/pmos-build/build.log
