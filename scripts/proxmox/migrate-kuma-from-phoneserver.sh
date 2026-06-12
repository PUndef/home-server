#!/usr/bin/env bash
# Migrate Uptime Kuma from phoneserver to static-sites LXC (102).
#
# 1. Backup kuma data from phoneserver
# 2. Install Kuma on LXC (if needed)
# 3. Restore data + fix hosts/monitors
# 4. Stop Kuma on phoneserver
#
# Usage (WSL):
#   ./migrate-kuma-from-phoneserver.sh
#   PHONE_IP=192.168.1.227 LXC_VMID=102 ./migrate-kuma-from-phoneserver.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PHONE_IP="${PHONE_IP:-192.168.1.227}"
PHONE_USER="${PHONE_USER:-pmos}"
PHONE_KEY="${PHONE_KEY:-$HOME/.ssh/phoneserver_nopass}"
LXC_VMID="${LXC_VMID:-102}"
KUMA_VERSION="${KUMA_VERSION:-2.3.2}"
TMP_BACKUP="${TMP_BACKUP:-/tmp/kuma-data-migrate.tar.gz}"

if [[ ! -f "${PHONE_KEY}" ]]; then
  echo "missing SSH key: ${PHONE_KEY}" >&2
  exit 1
fi

SSH_PHONE=(ssh -o StrictHostKeyChecking=no -i "${PHONE_KEY}" "${PHONE_USER}@${PHONE_IP}")
SCP_PHONE=(scp -o StrictHostKeyChecking=no -i "${PHONE_KEY}")

proxmox() {
  python3 "${REPO_ROOT}/scripts/proxmox/proxmox_exec.py" "$@"
}

echo "=== 1. backup kuma data from phoneserver (${PHONE_IP}) ==="
"${SSH_PHONE[@]}" "sudo rc-service uptime-kuma stop 2>/dev/null || true"
"${SSH_PHONE[@]}" "sudo tar -czf /tmp/kuma-data-migrate.tar.gz -C /var/lib/uptime-kuma data"
"${SCP_PHONE[@]}" "${PHONE_USER}@${PHONE_IP}:/tmp/kuma-data-migrate.tar.gz" "${TMP_BACKUP}"
ls -lh "${TMP_BACKUP}"

echo "=== 2. push install scripts to Proxmox host ==="
python3 "${REPO_ROOT}/scripts/proxmox/upload.py" "${REPO_ROOT}/scripts/proxmox/uptime-kuma-install.sh" /tmp/uptime-kuma-install.sh --chmod 755
python3 "${REPO_ROOT}/scripts/proxmox/upload.py" "${REPO_ROOT}/scripts/proxmox/fix-kuma-monitors-lxc.sh" /tmp/fix-kuma-monitors-lxc.sh --chmod 755
python3 "${REPO_ROOT}/scripts/proxmox/upload.py" "${TMP_BACKUP}" /tmp/kuma-data-migrate.tar.gz

proxmox "pct push ${LXC_VMID} /tmp/uptime-kuma-install.sh /tmp/uptime-kuma-install.sh --perms 0755"
proxmox "pct push ${LXC_VMID} /tmp/fix-kuma-monitors-lxc.sh /tmp/fix-kuma-monitors-lxc.sh --perms 0755"
proxmox "pct push ${LXC_VMID} /tmp/kuma-data-migrate.tar.gz /tmp/kuma-data-migrate.tar.gz"

echo "=== 3. install Kuma on LXC ${LXC_VMID} ==="
proxmox "pct exec ${LXC_VMID} -- bash -lc 'KUMA_VERSION=${KUMA_VERSION} /tmp/uptime-kuma-install.sh'"

echo "=== 4. restore data from phoneserver backup ==="
proxmox "pct exec ${LXC_VMID} -- bash -lc '
  systemctl stop uptime-kuma
  rm -rf /var/lib/uptime-kuma/data
  tar -xzf /tmp/kuma-data-migrate.tar.gz -C /var/lib/uptime-kuma
  chown -R uptime-kuma:uptime-kuma /var/lib/uptime-kuma
'"

echo "=== 5. fix hosts + monitor TLS flags ==="
proxmox "pct exec ${LXC_VMID} -- bash /tmp/fix-kuma-monitors-lxc.sh"

echo "=== 6. disable Kuma on phoneserver ==="
"${SSH_PHONE[@]}" "sudo rc-update del uptime-kuma default 2>/dev/null || true; sudo rc-service uptime-kuma stop 2>/dev/null || true"

proxmox "pct exec ${LXC_VMID} -- rm -f /tmp/uptime-kuma-install.sh /tmp/fix-kuma-monitors-lxc.sh /tmp/kuma-data-migrate.tar.gz"
proxmox "rm -f /tmp/uptime-kuma-install.sh /tmp/fix-kuma-monitors-lxc.sh /tmp/kuma-data-migrate.tar.gz"
rm -f "${TMP_BACKUP}"

echo ""
echo "done — Uptime Kuma: http://192.168.50.35:3001/"
echo "phoneserver Kuma stopped; Beszel still on phoneserver for host metrics"
