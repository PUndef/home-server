#!/usr/bin/env python3
"""Remove duplicate/broken Kuma monitors and fix HTTP status codes on LXC 102."""

from __future__ import annotations

import os
import sys

import paramiko

DEFAULT_KEY = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)
VMID = os.environ.get("KUMA_LXC_VMID", "102")
DB = "/var/lib/uptime-kuma/data/kuma.db"

# Redundant with Public HTTPS + ping on same host.
DELETE_NAMES = (
    "Nextcloud (LAN)",
    "OwnCord backend (LAN)",
    "static-sites LXC",
    "OpenWrt router",
    "Home Assistant",
    "Home Assistant UI",
)

# name -> (field, value) patches
PATCHES = {
    "Requiem (static)": ("url", "http://192.168.50.35/requiem/"),
    "Home Assistant (phoneserver)": ("url", "http://192.168.50.127:8123/"),
}

# name -> parent group id (from kuma seed groups order: 1=Public, 2=srv, 3=LAN, 4=VPS)
MOVE_TO_SRV = (
    "Home Assistant (phoneserver)",
    "phoneserver",
)


def run_sql(client: paramiko.SSHClient, sql: str) -> str:
    _stdin, stdout, stderr = client.exec_command(
        f"pct exec {VMID} -- sqlite3 {DB} {sql!r}",
        timeout=30,
    )
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

    print("=== delete redundant monitors ===")
    for name in DELETE_NAMES:
        out = run_sql(client, f"DELETE FROM monitor WHERE name='{name}';")
        print(f"removed: {name} ({out or 'ok'})")

    print("=== patch URLs ===")
    for name, (field, value) in PATCHES.items():
        sql = f"UPDATE monitor SET {field}='{value}' WHERE name='{name}';"
        run_sql(client, sql)
        print(f"patched {name}: {field}={value}")

    print("=== move monitors to srv group (parent=2) ===")
    for name in MOVE_TO_SRV:
        run_sql(client, f"UPDATE monitor SET parent=2 WHERE name='{name}';")
        print(f"moved: {name} -> srv")

    print("=== ensure phoneserver ping monitor ===")
    exists = run_sql(client, "SELECT id FROM monitor WHERE name='phoneserver';")
    if not exists:
        run_sql(
            client,
            "INSERT INTO monitor (name, active, type, parent, interval, hostname) "
            "VALUES ('phoneserver', 1, 'ping', 2, 60, '192.168.50.127');",
        )
        print("added: phoneserver ping")
    else:
        run_sql(
            client,
            "UPDATE monitor SET hostname='192.168.50.127', parent=2, active=1 "
            "WHERE name='phoneserver';",
        )
        print("updated: phoneserver ping")

    print("=== HTTP: accept 200-399, ignore_tls on https ===")
    run_sql(
        client,
        "UPDATE monitor SET accepted_statuscodes_json='[\"200-299\",\"300-399\"]' "
        "WHERE type='http';",
    )
    run_sql(
        client,
        "UPDATE monitor SET ignore_tls=1 WHERE type='http' AND url LIKE 'https://%';",
    )
    run_sql(client, "UPDATE monitor SET ignore_tls=0 WHERE type='http' AND url LIKE 'http://%';")

    print("=== result ===")
    sql = (
        "SELECT id,name,type,COALESCE(url,hostname),ignore_tls "
        "FROM monitor WHERE type!='group' ORDER BY parent,id;"
    )
    print(run_sql(client, sql))

    client.exec_command(f"pct exec {VMID} -- systemctl restart uptime-kuma", timeout=30)
    print("restarted uptime-kuma")
    client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
