#!/usr/bin/env python3
"""List all Uptime Kuma monitors on LXC 102."""

from __future__ import annotations

import os
import sys

import paramiko

DEFAULT_KEY = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)


def main() -> int:
    for cls in (paramiko.RSAKey, paramiko.Ed25519Key, paramiko.ECDSAKey):
        try:
            key = cls.from_private_key_file(DEFAULT_KEY)
            break
        except paramiko.SSHException:
            continue
    else:
        print("no proxmox key", file=sys.stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(os.environ.get("PROXMOX_HOST", "192.168.50.9"), username="root", pkey=key, timeout=10)

    sql = (
        "SELECT id, active, name, type, "
        "COALESCE(url,''), COALESCE(hostname,''), COALESCE(port,''), "
        "COALESCE(parent,''), ignore_tls "
        "FROM monitor ORDER BY id;"
    )
    _stdin, stdout, stderr = client.exec_command(
        f"pct exec 102 -- sqlite3 -header -column /var/lib/uptime-kuma/data/kuma.db {sql!r}",
        timeout=30,
    )
    print(stdout.read().decode())
    err = stderr.read().decode()
    if err:
        print(err, file=sys.stderr)
    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
