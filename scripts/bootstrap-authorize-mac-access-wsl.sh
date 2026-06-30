#!/usr/bin/env bash
# Authorize a public key on home-server infrastructure using WSL ~/.ssh keys.

set -euo pipefail

PUBLIC_KEY="${PUBLIC_KEY:-}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pubkey)
      PUBLIC_KEY="${2:-}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PUBLIC_KEY" ]; then
  echo "missing --pubkey" >&2
  exit 2
fi

OPENWRT_KEY="${OPENWRT_KEY:-$HOME/.ssh/openwrt_ax300t_nopass}"
PHONE_KEY="${PHONE_KEY:-$HOME/.ssh/phoneserver_nopass}"
PROXMOX_KEY="${PROXMOX_KEY:-$HOME/.ssh/proxmox_pundef_nopass}"

for key in "$OPENWRT_KEY" "$PHONE_KEY" "$PROXMOX_KEY"; do
  if [ ! -f "$key" ]; then
    echo "missing SSH key in WSL: $key" >&2
    exit 1
  fi
  chmod 600 "$key" 2>/dev/null || true
done

add_key() {
  local name="$1"
  local remote="$2"
  local key="$3"

  echo "=== $name ($remote) ==="
  ssh -i "$key" \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    "$remote" \
    "umask 077; mkdir -p ~/.ssh; touch ~/.ssh/authorized_keys; grep -qxF '$PUBLIC_KEY' ~/.ssh/authorized_keys || printf '%s\n' '$PUBLIC_KEY' >> ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys; echo authorized"
}

add_key "OpenWrt" "root@192.168.1.1" "$OPENWRT_KEY"
add_key "phoneserver wlan" "user@192.168.1.227" "$PHONE_KEY"
add_key "Proxmox" "root@192.168.50.9" "$PROXMOX_KEY"
add_key "static-sites deploy" "deploy@192.168.50.35" "$PROXMOX_KEY"

echo
echo "Done. Mac key authorized: $PUBLIC_KEY"
