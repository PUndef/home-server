#!/usr/bin/env python3
"""Set ignore_tls on HTTPS monitors in Kuma DB on LXC 102."""

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
    key = None
    for cls in (paramiko.RSAKey, paramiko.Ed25519Key, paramiko.ECDSAKey):
        try:
            key = cls.from_private_key_file(DEFAULT_KEY)
            break
        except paramiko.SSHException:
            continue
    if not key:
        print("no proxmox key", file=sys.stderr)
        return 1

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(os.environ.get("PROXMOX_HOST", "192.168.50.9"), username="root", pkey=key, timeout=10)

    sql = (
        "UPDATE monitor SET ignore_tls=1 "
        "WHERE type='http' AND url LIKE 'https://%';"
    )
    cmds = [
        f"pct exec 102 -- sqlite3 /var/lib/uptime-kuma/data/kuma.db {sql!r}",
        "pct exec 102 -- sqlite3 /var/lib/uptime-kuma/data/kuma.db "
        "\"SELECT id,name,ignore_tls,url FROM monitor WHERE type='http';\"",
        "pct exec 102 -- systemctl restart uptime-kuma",
    ]
    for cmd in cmds:
        _stdin, stdout, stderr = client.exec_command(cmd, timeout=30)
        out = stdout.read().decode()
        err = stderr.read().decode()
        if out:
            print(out.rstrip())
        if err:
            print(err.rstrip(), file=sys.stderr)
    client.close()
    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
