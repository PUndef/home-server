#!/usr/bin/env bash
# Apply Kuma hosts/TLS fix on static-sites LXC (replaces old phoneserver-side script).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LXC_VMID="${LXC_VMID:-102}"

python3 "${REPO_ROOT}/scripts/proxmox/upload.py" \
    "${REPO_ROOT}/scripts/proxmox/fix-kuma-monitors-lxc.sh" \
    /tmp/fix-kuma-monitors-lxc.sh --chmod 755

python3 "${REPO_ROOT}/scripts/proxmox/proxmox_exec.py" \
    "pct push ${LXC_VMID} /tmp/fix-kuma-monitors-lxc.sh /tmp/fix-kuma-monitors-lxc.sh --perms 0755"

python3 "${REPO_ROOT}/scripts/proxmox/proxmox_exec.py" \
    "pct exec ${LXC_VMID} -- bash /tmp/fix-kuma-monitors-lxc.sh"

python3 "${REPO_ROOT}/scripts/proxmox/proxmox_exec.py" \
    "pct exec ${LXC_VMID} -- rm -f /tmp/fix-kuma-monitors-lxc.sh"

python3 "${REPO_ROOT}/scripts/proxmox/proxmox_exec.py" \
    "rm -f /tmp/fix-kuma-monitors-lxc.sh"

echo "done — check http://192.168.50.35:3001/"
