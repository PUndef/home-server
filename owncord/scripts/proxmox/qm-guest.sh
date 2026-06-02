#!/usr/bin/env bash
# Helpers for qm guest exec on Proxmox host.
# The qm CLI often exits 0 even when the guest command failed; parse JSON exitcode.

qm_guest_rc() {
  local out rc
  out="$(qm guest exec "$@" 2>&1)" || {
    echo "$out" >&2
    return 1
  }
  printf '%s\n' "$out"
  rc="$(printf '%s' "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("exitcode", 1))' 2>/dev/null || echo 1)"
  [[ "${rc}" == "0" ]]
}
