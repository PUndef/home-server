#!/usr/bin/env python3
"""Replace OpenWrt SSH monitor — srv subnet cannot reach router admin (fw4 reject on lan2)."""

from __future__ import annotations

import os
import sys
import time

import paramiko

DEFAULT_KEY = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)
VMID = os.environ.get("KUMA_LXC_VMID", "102")
DB = "/var/lib/uptime-kuma/data/kuma.db"


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

    def run(cmd: str, timeout: int = 60) -> str:
        _stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
        out = stdout.read().decode().strip()
        err = stderr.read().decode().strip()
        if err:
            print(err, file=sys.stderr)
        return out

    sql = (
        "UPDATE monitor SET type='ping', hostname='1.1.1.1', port=NULL, "
        "name='Internet uplink (1.1.1.1)' "
        "WHERE hostname='192.168.1.1' AND type='port' AND port=22;"
    )
    run(f"pct exec {VMID} -- sqlite3 {DB} {sql!r}")
    print("updated router monitor -> ping 1.1.1.1")

    run(f"pct exec {VMID} -- systemctl restart uptime-kuma")
    print("restarted uptime-kuma, waiting 70s...")
    time.sleep(70)

    status_sql = (
        "SELECT m.id, m.name, m.type, m.hostname, h.status, h.msg "
        "FROM monitor m "
        "LEFT JOIN heartbeat h ON h.monitor_id=m.id "
        "AND h.id=(SELECT MAX(id) FROM heartbeat WHERE monitor_id=m.id) "
        "WHERE m.type!='group' OR m.parent IS NULL ORDER BY m.id;"
    )
    print(run(f"pct exec {VMID} -- sqlite3 -header -column {DB} {status_sql!r}"))

    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
