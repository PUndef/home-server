#!/bin/bash
# WSL/Linux deploy of routing status collector to phoneserver.
set -eu

_repo="$(cd "$(dirname "$0")/../.." && pwd)"
_phone_ip="${PHONE_IP:-192.168.1.227}"
_ssh_user="${SSH_USER:-user}"
_ssh_key="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
_staging="/tmp/routing-status-install-$$"
_remote_staging="/tmp/routing-status-install"

if [ ! -f "$_ssh_key" ]; then
  echo "missing phoneserver key: $_ssh_key" >&2
  exit 1
fi

_openwrt_key="${OPENWRT_KEY:-/mnt/c/Users/PUndef-PC/.ssh/openwrt_ax300t_nopass}"
_lxc_key="${LXC_KEY:-/mnt/c/Users/PUndef-PC/.ssh/proxmox_pundef_nopass}"
if [ ! -f "$_openwrt_key" ]; then
  _openwrt_key="$HOME/.ssh/openwrt_ax300t_nopass"
fi
if [ ! -f "$_lxc_key" ]; then
  _lxc_key="$HOME/.ssh/proxmox_pundef_nopass"
fi

_ssh_opts=(-i "$_ssh_key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)
_remote="${_ssh_user}@${_phone_ip}"

rm -rf "$_staging"
mkdir -p "$_staging"
cp "$_repo/scripts/openwrt/routing_status.py" "$_staging/"
cp "$_repo/config/openwrt/overrides.json" "$_staging/"
cp "$_repo/scripts/phoneserver/routing-status-collector.sh" "$_staging/"
cp "$_repo/scripts/phoneserver/routing-status-collector.service" "$_staging/"
cp "$_repo/scripts/phoneserver/routing-status-collector.timer" "$_staging/"
cp "$_repo/scripts/phoneserver/install-routing-status-collector.sh" "$_staging/"
cp "$_openwrt_key" "$_staging/openwrt_collector"
cp "$_lxc_key" "$_staging/lxc_deploy_key"
chmod 600 "$_staging/openwrt_collector" "$_staging/lxc_deploy_key"

echo "=== install routing status collector on $_remote ==="
ssh "${_ssh_opts[@]}" "$_remote" "echo ok"
ssh "${_ssh_opts[@]}" "$_remote" "rm -rf '$_remote_staging' && mkdir -p '$_remote_staging'"
scp -r "${_ssh_opts[@]}" "$_staging"/* "$_remote:$_remote_staging/"
ssh "${_ssh_opts[@]}" "$_remote" "chmod 755 '$_remote_staging/install-routing-status-collector.sh' && sudo '$_remote_staging/install-routing-status-collector.sh'"
rm -rf "$_staging"
echo "done"
