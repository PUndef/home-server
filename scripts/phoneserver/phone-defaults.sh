#!/bin/bash
# Default PHONE_IP / SSH_KEY from hosts.yaml unless already exported.
# Usage: source "$(dirname "$0")/phone-defaults.sh"

_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_hosts_yaml="${_script_dir}/hosts.yaml"

if [[ -f "$_hosts_yaml" && -z "${PHONE_IP:-}" ]]; then
  _host_id="${PHONE_HOST:-$(grep '^default_host:' "$_hosts_yaml" | awk '{print $2}')}"
  PHONE_IP=$(awk -v id="$_host_id" '
    $0 ~ "^  " id ":" { found=1; next }
    found && /^  [a-z]/ { exit }
    found && /lan_ip:/ { print $2; exit }
  ' "$_hosts_yaml")
  export PHONE_IP="${PHONE_IP:-172.16.42.1}"
elif [[ -z "${PHONE_IP:-}" ]]; then
  export PHONE_IP=172.16.42.1
fi

export SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
