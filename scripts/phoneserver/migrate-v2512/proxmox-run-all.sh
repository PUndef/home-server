#!/bin/bash
# Full pipeline on Proxmox. Logs: /root/pmos-build/run-all.log
# Status:  cat /root/pmos-build/status.txt
set -euo pipefail

STATUS=/root/pmos-build/status.txt
LOG=/root/pmos-build/run-all.log
PMAP=/root/.local/var/pmbootstrap/cache_git/pmaports

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
set_status() { echo "$1" > "$STATUS"; echo "$(date -Is) $1" >> "$LOG"; }

exec >>"$LOG" 2>&1
set_status "STARTED"

sed -i 's/\r$//' /root/pmos-build/migrate-v2512/*.sh /root/pmos-build/migrate-v2512/*.exp 2>/dev/null || true

PYFILE="$(python3 -c 'import pmb.install._install as i, os; print(os.path.dirname(i.__file__))')/_install.py"
grep -q 'patched for joyeuse' "$PYFILE" || \
    sed -i 's|if int(config.boot_size) >= int(default):|if True:  # patched for joyeuse|' "$PYFILE"

if [ ! -f "$PMAP/channels.cfg" ]; then
    log "cloning pmaports v25.12..."
    rm -rf "$PMAP"
    git clone --depth 1 --branch v25.12 \
        https://gitlab.postmarketos.org/postmarketOS/pmaports.git "$PMAP"
fi

cd "$PMAP"
git fetch origin main --depth=1 2>/dev/null || true
git update-ref refs/remotes/origin/main FETCH_HEAD 2>/dev/null || true
git show origin/main:channels.cfg > channels.cfg

if [ ! -d /root/.local/var/pmbootstrap/chroot_native ]; then
    set_status "INIT"
    log "pmbootstrap init..."
    pmbootstrap --as-root shutdown 2>/dev/null || true
    export PMB_AS_ROOT=1
    expect /root/pmos-build/migrate-v2512/pmbootstrap-init-v2512.exp
    pmbootstrap --as-root config boot_size 256
    pmbootstrap --as-root config ui none
    pmbootstrap --as-root config hostname phoneserver
    pmbootstrap --as-root config user pmos
fi

set_status "INSTALLING"
log "pmbootstrap install (30-90 min)..."
pmbootstrap --as-root config boot_size 256
pmbootstrap --as-root install --no-fde --password changemenow --split

set_status "PATCHING_BOOTIMG"
bash /root/pmos-build/migrate-v2512/build-headless.sh || true

set_status "DONE"
log "artifacts:"
ls -lah /root/.local/var/pmbootstrap/chroot_native/home/pmos/rootfs/*.img /root/pmos-artifacts/u-boot-sm7125.img
