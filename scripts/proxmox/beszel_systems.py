#!/usr/bin/env python3
"""List Beszel hub systems from PocketBase SQLite on LXC 102."""

from __future__ import annotations

import os
import sys

import paramiko

KEY = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)
DB = "/opt/beszel/beszel_data/data.db"


def main() -> int:
    for cls in (paramiko.RSAKey, paramiko.Ed25519Key, paramiko.ECDSAKey):
        try:
            key = cls.from_private_key_file(KEY)
            break
        except paramiko.SSHException:
            continue
    else:
        return 1

    c = paramiko.SSHClient()
    c.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    c.connect(os.environ.get("PROXMOX_HOST", "192.168.50.9"), username="root", pkey=key, timeout=10)

    for sql in (
        ".tables",
        "SELECT id,name,host,status,updated FROM systems ORDER BY name;",
    ):
        _stdin, stdout, stderr = c.exec_command(
            f"pct exec 102 -- sqlite3 {DB} {sql!r}",
            timeout=30,
        )
        print(f"--- {sql} ---")
        print(stdout.read().decode() or "(empty)")
        err = stderr.read().decode().strip()
        if err:
            print(err, file=sys.stderr)
    c.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
