#!/usr/bin/env bash
# apply-vm-file.sh
#
# Run on the Proxmox host. Pushes a file from the host filesystem into a
# guest VM via QEMU guest agent (no SSH key required), optionally runs a
# follow-up command inside the VM.
#
# Usage:
#   apply-vm-file.sh <vmid> <local-path-on-host> <remote-path-in-vm> [<post-cmd>]
#
# Example:
#   ./apply-vm-file.sh 101 /tmp/apps-pundef.conf \
#     /etc/apache2/sites-available/apps-pundef.conf \
#     "a2enmod -q proxy_wstunnel rewrite headers && apache2ctl configtest && systemctl reload apache2"

set -euo pipefail

VMID="${1:?vmid is required}"
LOCAL_FILE="${2:?local file path is required}"
REMOTE_FILE="${3:?remote target path is required}"
POST_CMD="${4:-}"

if [[ ! -f "${LOCAL_FILE}" ]]; then
    echo "[apply-vm-file] local file not found: ${LOCAL_FILE}" >&2
    exit 1
fi

SIZE="$(wc -c < "${LOCAL_FILE}")"
B64="$(base64 -w0 "${LOCAL_FILE}")"
echo "[apply-vm-file] vm=${VMID} local=${LOCAL_FILE} (${SIZE}B) -> ${REMOTE_FILE}"

# Use printf %s to avoid trailing newline issues; base64 -d in the guest
# happily ignores whitespace anyway.
qm guest exec "${VMID}" --timeout 30 -- bash -c \
    "printf '%s' '${B64}' | base64 -d > '${REMOTE_FILE}' && wc -c '${REMOTE_FILE}'"

if [[ -n "${POST_CMD}" ]]; then
    echo "[apply-vm-file] running post-cmd in vm ${VMID}: ${POST_CMD}"
    qm guest exec "${VMID}" --timeout 30 -- bash -lc "${POST_CMD}"
fi

echo "[apply-vm-file] done"
