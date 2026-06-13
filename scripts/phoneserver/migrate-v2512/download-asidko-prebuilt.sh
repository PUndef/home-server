#!/bin/bash
# Download asidko v25.12 prebuilt images to ARTIFACT_DIR (Proxmox or WSL).
# Same kernel 6.14.7-sm7125 as pm6150-charger v0.6.2 — no pmbootstrap build needed.
set -euo pipefail

ARTIFACT_DIR="${ARTIFACT_DIR:-/root/pmos-artifacts/asidko}"
REPO="asidko/redmi-note-9s-postmarketos"
BASE="https://github.com/${REPO}/releases/latest/download"

mkdir -p "$ARTIFACT_DIR"
cd "$ARTIFACT_DIR"

for f in SHA256SUMS u-boot-sm7125.img xiaomi-miatoll-boot.img.zst xiaomi-miatoll-root.img.zst; do
    echo "==> $f"
    curl -fL --retry 3 --retry-delay 5 -o "$f" "${BASE}/${f}"
done

echo "==> decompress"
zstd -d --force xiaomi-miatoll-boot.img.zst
zstd -d --force xiaomi-miatoll-root.img.zst

sha256sum -c SHA256SUMS
ls -lah xiaomi-miatoll-boot.img xiaomi-miatoll-root.img u-boot-sm7125.img
echo "READY: flash with flash-asidko-prebuilt.sh"
