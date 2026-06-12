#!/usr/bin/env bash
# Install Uptime Kuma on static-sites LXC (102). No phoneserver backup.
#
# Usage (PowerShell / WSL):
#   py -3 scripts/proxmox/proxmox_exec.py "pct exec 102 -- bash /tmp/uptime-kuma-install.sh"
# Or:
#   bash scripts/proxmox/install-uptime-kuma.sh
#
# After install: create admin in http://192.168.50.35:3001/
# Then seed: KUMA_URL=http://192.168.50.35:3001 KUMA_USERNAME=... KUMA_PASSWORD=... \
#   bash scripts/phoneserver/seed-kuma-monitors.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LXC_VMID="${LXC_VMID:-102}"
KUMA_VERSION="${KUMA_VERSION:-2.3.2}"

PYTHON="${PYTHON:-python3}"
if command -v py >/dev/null 2>&1; then
  PYTHON="py -3"
fi

exec_cmd() {
  # shellcheck disable=SC2086
  $PYTHON "${REPO_ROOT}/scripts/proxmox/proxmox_exec.py" "$@"
}

upload_cmd() {
  # shellcheck disable=SC2086
  $PYTHON "${REPO_ROOT}/scripts/proxmox/upload.py" "$@"
}

echo "=== upload install + hosts fix scripts ==="
upload_cmd "${REPO_ROOT}/scripts/proxmox/uptime-kuma-install.sh" /tmp/uptime-kuma-install.sh --chmod 755
upload_cmd "${REPO_ROOT}/scripts/proxmox/fix-kuma-monitors-lxc.sh" /tmp/fix-kuma-monitors-lxc.sh --chmod 755

echo "=== pct push LXC ${LXC_VMID} ==="
exec_cmd "pct push ${LXC_VMID} /tmp/uptime-kuma-install.sh /tmp/uptime-kuma-install.sh --perms 0755"
exec_cmd "pct push ${LXC_VMID} /tmp/fix-kuma-monitors-lxc.sh /tmp/fix-kuma-monitors-lxc.sh --perms 0755"

echo "=== install Kuma (npm may take 5-15 min) ==="
exec_cmd "pct exec ${LXC_VMID} -- bash -lc 'KUMA_VERSION=${KUMA_VERSION} /tmp/uptime-kuma-install.sh'"

echo "=== /etc/hosts for *.mooo.com split-horizon ==="
exec_cmd "pct exec ${LXC_VMID} -- bash /tmp/fix-kuma-monitors-lxc.sh"

echo "=== cleanup temp on host/LXC ==="
exec_cmd "pct exec ${LXC_VMID} -- rm -f /tmp/uptime-kuma-install.sh /tmp/fix-kuma-monitors-lxc.sh"
exec_cmd "rm -f /tmp/uptime-kuma-install.sh /tmp/fix-kuma-monitors-lxc.sh"

echo ""
echo "done — http://192.168.50.35:3001/"
echo "next: create admin, then seed-kuma-monitors.sh with KUMA_URL=http://192.168.50.35:3001"
