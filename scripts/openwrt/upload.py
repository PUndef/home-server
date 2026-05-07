"""Upload a local file to OpenWrt over SSH (without SFTP).

Usage:
  python scripts/openwrt/upload.py <local_path> <remote_path> [--chmod 0755]

Approach: read local bytes, base64-encode, send through `base64 -d > remote`
inside a single `sh -c` invocation. Avoids PowerShell/heredoc escaping issues
and works on dropbear (no SFTP).
"""

from __future__ import annotations

import argparse
import base64
import os
import sys

import paramiko


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

    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    user = os.environ.get("OPENWRT_USER", "root")
    key_path = os.environ.get(
        "OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass"
    )

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = load_private_key(key_path)
    client.connect(host, username=user, pkey=key, timeout=10)

    try:
        # Stream encoded payload via stdin to avoid argument-length / quoting issues.
        cmd = f"base64 -d > {args.remote_path}"
        if args.chmod:
            cmd += f" && chmod {args.chmod} {args.remote_path}"
        cmd += f" && wc -c {args.remote_path}"
        stdin, stdout, stderr = client.exec_command(cmd, timeout=30)
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
