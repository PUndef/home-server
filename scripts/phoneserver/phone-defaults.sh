#!/bin/bash
# Default PHONE_IP / SSH_KEY from hosts.yaml unless already exported.
# PHONE_DEFAULT=lan|usb — which IP when PHONE_IP is unset (default: lan).
# PHONE_HOST=<id> — host block in hosts.yaml (default: default_host).
# Usage: source /path/to/phone-defaults.sh

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_hosts_yaml="${_script_dir}/hosts.yaml"
_phone_default="${PHONE_DEFAULT:-lan}"

_yaml_ip() {
  local field="$1"
  local host_id="${PHONE_HOST:-$(grep '^default_host:' "$_hosts_yaml" | awk '{print $2}')}"
  awk -v id="$host_id" -v field="$field:" '
    $0 ~ "^  " id ":" { found=1; next }
    found && /^  [a-zA-Z0-9_-]+:/ && index($0, field) == 0 { exit }
    found && index($0, field) { print $2; exit }
  ' "$_hosts_yaml"
}

if [[ -z "${PHONE_IP:-}" ]]; then
  if [[ -f "$_hosts_yaml" ]]; then
    if [[ "$_phone_default" == "usb" ]]; then
      PHONE_IP="$(_yaml_ip usb_ip)"
    else
      PHONE_IP="$(_yaml_ip lan_ip)"
    fi
    export PHONE_IP="${PHONE_IP:-172.16.42.1}"
  else
    export PHONE_IP=172.16.42.1
  fi
fi

export SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
