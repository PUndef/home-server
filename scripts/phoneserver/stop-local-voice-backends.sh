#!/bin/bash
# Stop unused Wyoming whisper/piper on phoneserver (production uses Yandex cloud STT/TTS).
# Run from WSL: PHONE_IP=192.168.1.227 bash scripts/phoneserver/stop-local-voice-backends.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PHONE_DEFAULT=lan source "${SCRIPT_DIR}/phone-defaults.sh"

SSH_OPTS=(-o StrictHostKeyChecking=no -i "$SSH_KEY")

echo "[stop-local] target pmos@${PHONE_IP}"

ssh "${SSH_OPTS[@]}" "pmos@${PHONE_IP}" sh -s <<'REMOTE'
set -eu
cd /opt/homeassistant

for c in wyoming-whisper wyoming-piper; do
  if sudo docker ps -a --format '{{.Names}}' | grep -qx "$c"; then
    sudo docker stop "$c" 2>/dev/null || true
    sudo docker rm "$c" 2>/dev/null || true
    echo "[stop-local] removed $c"
  fi
done

sudo docker compose ps
REMOTE

echo "[stop-local] done — HA unchanged; see docs/phoneserver/voice-assistant.md"
