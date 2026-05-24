"""Run a single shell command on a VPS over SSH.

Mirrors scripts/proxmox/proxmox_exec.py. Target via env vars:

- VPS_HOST  - required
- VPS_USER  - default "root"
- VPS_KEY   - default %USERPROFILE%/.ssh/vps_nopass

Examples:
    set VPS_HOST=89.44.76.52
    python scripts/vps/vps_exec.py hostname
    python scripts/vps/vps_exec.py "bash /tmp/install.sh"
"""

from __future__ import annotations

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
    if len(sys.argv) < 2:
        print("usage: python scripts/vps/vps_exec.py <command>")
        return 2

    host = os.environ.get("VPS_HOST", "")
    if not host:
        print("VPS_HOST is required", file=sys.stderr)
        return 2

    user = os.environ.get("VPS_USER", "root")
    key_path = os.environ.get("VPS_KEY", DEFAULT_KEY_PATH)
    cmd = " ".join(sys.argv[1:])

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = load_private_key(key_path)
    client.connect(host, username=user, pkey=key, timeout=15)

    try:
        _stdin, stdout, stderr = client.exec_command(cmd, timeout=300)
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        if out:
            sys.stdout.buffer.write(out.encode("utf-8", errors="ignore"))
        if err:
            sys.stderr.buffer.write(err.encode("utf-8", errors="ignore"))
        return stdout.channel.recv_exit_status()
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
