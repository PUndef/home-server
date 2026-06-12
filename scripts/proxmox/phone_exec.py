#!/usr/bin/env python3
"""Run a command on phoneserver via Proxmox jump (lan PC cannot reach srv hosts)."""

from __future__ import annotations

import io
import os
import subprocess
import sys

import paramiko

PROXMOX_HOST = os.environ.get("PROXMOX_HOST", "192.168.50.9")
PHONE_HOST = os.environ.get("PHONE_HOST", os.environ.get("PHONE_IP", "192.168.50.127"))
PHONE_USER = os.environ.get("PHONE_USER", "pmos")

PROXMOX_KEY = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)


def load_phone_key() -> paramiko.PKey:
    wsl_key = subprocess.run(
        ["wsl", "bash", "-lc", "cat ~/.ssh/phoneserver_nopass"],
        capture_output=True,
        check=False,
    )
    if wsl_key.returncode == 0 and wsl_key.stdout:
        bio = io.StringIO(wsl_key.stdout.decode())
        for cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
            try:
                bio.seek(0)
                return cls.from_private_key(bio)
            except paramiko.SSHException:
                continue
    raise SystemExit("phoneserver SSH key not found in WSL ~/.ssh/phoneserver_nopass")


def load_proxmox_key() -> paramiko.PKey:
    for cls in (paramiko.RSAKey, paramiko.Ed25519Key, paramiko.ECDSAKey):
        try:
            return cls.from_private_key_file(PROXMOX_KEY)
        except paramiko.SSHException:
            continue
    raise SystemExit(f"proxmox key not found: {PROXMOX_KEY}")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: phone_exec.py <remote-command>")
        return 2

    cmd = " ".join(sys.argv[1:])
    phone_key = load_phone_key()
    px_key = load_proxmox_key()

    px = paramiko.SSHClient()
    px.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    px.connect(PROXMOX_HOST, username="root", pkey=px_key, timeout=10)

    tr = px.get_transport()
    if tr is None:
        raise SystemExit("no proxmox transport")

    chan = tr.open_channel("direct-tcpip", (PHONE_HOST, 22), ("127.0.0.1", 0))
    phone = paramiko.SSHClient()
    phone.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    phone.connect(PHONE_HOST, username=PHONE_USER, pkey=phone_key, sock=chan, timeout=15)

    _stdin, stdout, stderr = phone.exec_command(cmd, timeout=120)
    out = stdout.read().decode()
    err = stderr.read().decode()
    if out:
        print(out, end="" if out.endswith("\n") else "\n")
    if err:
        print(err, file=sys.stderr, end="" if err.endswith("\n") else "\n")

    phone.close()
    px.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
