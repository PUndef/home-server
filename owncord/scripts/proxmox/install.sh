#!/usr/bin/env bash
# OwnCord install inside LXC 103 (Debian). Run via:
#   upload to Proxmox /tmp, pct push 103, pct exec 103 -- bash /tmp/owncord-install.sh
#
# Optional env:
#   REGISTRATION_CODE=secret   — invite code for new accounts
#   OWNCORD_REPO=https://github.com/Restezzz/OwnCord.git

set -euo pipefail

REPO="${OWNCORD_REPO:-https://github.com/Restezzz/OwnCord.git}"
BUILD_DIR="/tmp/owncord-src"
REG_CODE="${REGISTRATION_CODE:-}"

log() { echo "[owncord-install] $*"; }

log "Removing abandoned chat stacks (if any)..."
rm -rf /opt/spacebar.abandoned-* /opt/stoat.bak.* /opt/stoat /opt/spacebar 2>/dev/null || true
command -v docker >/dev/null 2>&1 && docker ps -aq 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true

log "Installing git/curl..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates openssl rsync

log "Cloning ${REPO}..."
rm -rf "${BUILD_DIR}"
git clone --depth 1 "${REPO}" "${BUILD_DIR}"
cd "${BUILD_DIR}"
sed -i 's/\r$//' deploy/install.sh 2>/dev/null || true
bash deploy/install.sh

if [[ -n "${REG_CODE}" ]]; then
  ENV="/opt/owncord/server/.env"
  if grep -q '^REGISTRATION_CODE=' "${ENV}"; then
    sed -i "s|^REGISTRATION_CODE=.*|REGISTRATION_CODE=${REG_CODE}|" "${ENV}"
  else
    echo "REGISTRATION_CODE=${REG_CODE}" >>"${ENV}"
  fi
  systemctl restart owncord
fi

log "Health check..."
sleep 3
curl -fsS http://127.0.0.1:3001/api/health
echo
systemctl --no-pager status owncord || true
