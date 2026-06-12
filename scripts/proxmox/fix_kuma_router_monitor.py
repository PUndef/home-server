#!/usr/bin/env python3
"""Change OpenWrt monitor from ping to port 22 (router blocks ICMP from srv)."""

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
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(os.environ.get("PROXMOX_HOST", "192.168.50.9"), username="root", pkey=key, timeout=10)

    sql = (
        "UPDATE monitor SET type='port', port=22, name='OpenWrt router SSH' "
        "WHERE name='OpenWrt router' AND hostname='192.168.1.1';"
    )
    _stdin, stdout, stderr = client.exec_command(
        f"pct exec 102 -- sqlite3 /var/lib/uptime-kuma/data/kuma.db {sql!r}",
        timeout=30,
    )
    print(stdout.read().decode() or "updated")
    client.exec_command("pct exec 102 -- systemctl restart uptime-kuma", timeout=30)
    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
