#!/usr/bin/env python3
"""Print HA internal_url from phoneserver via Proxmox jump."""

from __future__ import annotations

import json
import subprocess
import sys

from phone_exec import load_phone_key, load_proxmox_key

import paramiko

PROXMOX_HOST = "192.168.50.9"
PHONE_HOST = "192.168.50.127"


def main() -> int:
    px = paramiko.SSHClient()
    px.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    px.connect(PROXMOX_HOST, username="root", pkey=load_proxmox_key(), timeout=10)
    tr = px.get_transport()
    chan = tr.open_channel("direct-tcpip", (PHONE_HOST, 22), ("127.0.0.1", 0))
    phone = paramiko.SSHClient()
    phone.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    phone.connect(PHONE_HOST, username="pmos", pkey=load_phone_key(), sock=chan, timeout=15)
    _stdin, stdout, stderr = phone.exec_command(
        "cat /opt/homeassistant/config/.storage/core.config",
        timeout=30,
    )
    data = json.loads(stdout.read().decode())
    print("internal_url:", data["data"].get("internal_url"))
    print("external_url:", data["data"].get("external_url"))
    phone.close()
    px.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
