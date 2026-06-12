#!/usr/bin/env python3
"""Grant CAP_NET_RAW to uptime-kuma so ping monitors work in LXC 102."""

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
SERVICE = "/etc/systemd/system/uptime-kuma.service"


def run(client: paramiko.SSHClient, cmd: str, timeout: int = 60) -> str:
    _stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout)
    out = stdout.read().decode().strip()
    err = stderr.read().decode().strip()
    if err:
        print(err, file=sys.stderr)
    return out


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

    svc = run(client, f"pct exec {VMID} -- cat {SERVICE}")
    if "AmbientCapabilities=CAP_NET_RAW" in svc:
        print("already patched")
    else:
        lines = []
        for line in svc.splitlines():
            if line.strip() == "NoNewPrivileges=true":
                continue
            lines.append(line)
        insert = [
            "AmbientCapabilities=CAP_NET_RAW",
            "CapabilityBoundingSet=CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SETUID CAP_SETGID CAP_DAC_OVERRIDE",
            "NoNewPrivileges=false",
        ]
        out_lines: list[str] = []
        inserted = False
        for line in lines:
            out_lines.append(line)
            if not inserted and line.strip() == "[Service]":
                out_lines.extend(insert)
                inserted = True
        if not inserted:
            print("WARN: [Service] section not found", file=sys.stderr)
            return 1
        new_svc = "\n".join(out_lines) + "\n"
        # write via base64 to avoid quoting hell
        import base64

        b64 = base64.b64encode(new_svc.encode()).decode()
        run(client, f"pct exec {VMID} -- bash -c 'echo {b64} | base64 -d > {SERVICE}'")
        print("patched systemd unit")

    run(client, f"pct exec {VMID} -- systemctl daemon-reload")
    run(client, f"pct exec {VMID} -- systemctl restart uptime-kuma")
    print("active:", run(client, f"pct exec {VMID} -- systemctl is-active uptime-kuma"))

    print("waiting 75s for monitor checks...")
    time.sleep(75)

    sql = (
        "SELECT m.name, h.status, substr(replace(h.msg,char(10),' '),1,80) "
        "FROM monitor m "
        "LEFT JOIN heartbeat h ON h.monitor_id=m.id "
        "AND h.id=(SELECT MAX(id) FROM heartbeat WHERE monitor_id=m.id) "
        "WHERE m.type!='group' ORDER BY m.id;"
    )
    print("=== all monitor status ===")
    print(
        run(
            client,
            f"pct exec {VMID} -- sqlite3 -header -column /var/lib/uptime-kuma/data/kuma.db {sql!r}",
        )
    )

    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
