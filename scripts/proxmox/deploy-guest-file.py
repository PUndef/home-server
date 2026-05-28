#!/usr/bin/env python3
"""Push a local file into a QEMU guest via base64 + qm guest exec."""

from __future__ import annotations

import argparse
import base64
import os
import sys

import paramiko

from proxmox_exec import DEFAULT_KEY_PATH, load_private_key


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("vmid", type=int)
    parser.add_argument("local_path")
    parser.add_argument("remote_path")
    parser.add_argument("--mode", default="644")
    args = parser.parse_args()

    raw = open(args.local_path, "rb").read().replace(b"\r\n", b"\n")
    payload = base64.b64encode(raw).decode("ascii")

    host = os.environ.get("PROXMOX_HOST", "192.168.50.9")
    user = os.environ.get("PROXMOX_USER", "root")
    key_path = os.environ.get("PROXMOX_KEY", DEFAULT_KEY_PATH)

    inner = (
        f"printf '%s' '{payload}' | base64 -d > '{args.remote_path}' "
        f"&& chmod {args.mode} '{args.remote_path}' "
        f"&& wc -c '{args.remote_path}'"
    )
    remote_cmd = f"qm guest exec {args.vmid} --timeout 60 -- bash -c {inner!r}"

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username=user, pkey=load_private_key(key_path), timeout=10)
    try:
        _stdin, stdout, stderr = client.exec_command(remote_cmd, timeout=120)
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        if out:
            print(out, end="")
        if err:
            print(err, file=sys.stderr, end="")
        return stdout.channel.recv_exit_status()
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
