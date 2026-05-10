"""Upload a local file to the Proxmox host (pundef) over SSH.

Mirrors scripts/openwrt/upload.py. Streams base64-encoded payload via
stdin to avoid argument-length / quoting issues.

Environment variables: PROXMOX_HOST, PROXMOX_USER, PROXMOX_KEY (see
proxmox_exec.py for defaults).
"""

from __future__ import annotations

import argparse
import base64
import os
import sys

import paramiko


DEFAULT_KEY_PATH = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    ".ssh",
    "proxmox_pundef_nopass",
)


def load_private_key(key_path: str) -> paramiko.PKey:
    last_error: Exception | None = None
    for cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        try:
            return cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last_error = exc
    raise last_error or paramiko.SSHException("Unsupported private key type")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("local_path")
    parser.add_argument("remote_path")
    parser.add_argument("--chmod", default="")
    args = parser.parse_args()

    with open(args.local_path, "rb") as f:
        data = f.read()
    encoded = base64.b64encode(data).decode("ascii")

    host = os.environ.get("PROXMOX_HOST", "192.168.50.9")
    user = os.environ.get("PROXMOX_USER", "root")
    key_path = os.environ.get("PROXMOX_KEY", DEFAULT_KEY_PATH)

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = load_private_key(key_path)
    client.connect(host, username=user, pkey=key, timeout=10)

    try:
        cmd = f"base64 -d > {args.remote_path}"
        if args.chmod:
            cmd += f" && chmod {args.chmod} {args.remote_path}"
        cmd += f" && wc -c {args.remote_path}"
        stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
        stdin.write(encoded)
        stdin.flush()
        stdin.channel.shutdown_write()
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        rc = stdout.channel.recv_exit_status()
        if out:
            sys.stdout.write(out)
        if err:
            sys.stderr.write(err)
        return rc
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
