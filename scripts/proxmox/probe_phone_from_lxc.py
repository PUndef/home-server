#!/usr/bin/env python3
"""Probe phoneserver reachability from LXC 102 (static-sites)."""

from __future__ import annotations

import os
import sys

import paramiko

KEY = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)
HOSTS = ("192.168.1.227", "172.16.42.1")


def main() -> int:
    for cls in (paramiko.RSAKey, paramiko.Ed25519Key, paramiko.ECDSAKey):
        try:
            key = cls.from_private_key_file(KEY)
            break
        except paramiko.SSHException:
            continue
    else:
        print("no ssh key", file=sys.stderr)
        return 1

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(os.environ.get("PROXMOX_HOST", "192.168.50.9"), username="root", pkey=key, timeout=10)

    script = r"""
for ip in 192.168.1.227; do
  echo "=== $ip ==="
  ping -c1 -W2 "$ip" 2>&1 | tail -1
  timeout 3 nc -zv "$ip" 22 2>&1 || true
done
echo "=== hub from lxc ==="
curl -sS -m5 -o /dev/null -w "beszel:%{http_code}\n" http://127.0.0.1:8090/api/health || true
"""
    _stdin, stdout, stderr = c.exec_command(f"pct exec 102 -- bash -c {script!r}", timeout=60)
    print(stdout.read().decode())
    err = stderr.read().decode().strip()
    if err:
        print(err, file=sys.stderr)
    c.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
