"""Upload a local file to a VPS over SSH (base64 stream, no SFTP).

Mirrors scripts/proxmox/upload.py. Target via env vars VPS_HOST, VPS_USER,
VPS_KEY (see vps_exec.py).
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
    "vps_nopass",
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
    parser.add_argument("--host", default="")
    parser.add_argument("--user", default="")
    parser.add_argument("--key", default="")
    parser.add_argument("--chmod", default="")
    args = parser.parse_args()

    host = args.host or os.environ.get("VPS_HOST", "")
    if not host:
        print("VPS_HOST is required (--host or env var)", file=sys.stderr)
        return 2

    user = args.user or os.environ.get("VPS_USER", "root")
    key_path = args.key or os.environ.get("VPS_KEY", DEFAULT_KEY_PATH)

    with open(args.local_path, "rb") as f:
        data = f.read()
    encoded = base64.b64encode(data).decode("ascii")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = load_private_key(key_path)
    client.connect(host, username=user, pkey=key, timeout=15)

    try:
        cmd = f"base64 -d > {args.remote_path}"
        if args.chmod:
            cmd += f" && chmod {args.chmod} {args.remote_path}"
        cmd += f" && wc -c {args.remote_path}"
        stdin, stdout, stderr = client.exec_command(cmd, timeout=120)
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
