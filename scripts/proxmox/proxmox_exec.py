"""Run a single shell command on the Proxmox host (pundef) over SSH.

Mirrors scripts/openwrt/openwrt_exec.py. Useful for the agent / scripts
to check VM/host state and run `qm guest exec <vmid> -- ...` against
the VMs themselves without copy-paste.

Environment variables (with sane defaults):
- PROXMOX_HOST  - default "192.168.50.9"
- PROXMOX_USER  - default "root"
- PROXMOX_KEY   - default %USERPROFILE%/.ssh/proxmox_pundef_nopass

Examples:
    python scripts/proxmox/proxmox_exec.py "pveversion -v | head"
    python scripts/proxmox/proxmox_exec.py "qm list"
    python scripts/proxmox/proxmox_exec.py "qm guest exec 101 -- curl -s ifconfig.me"
"""

from __future__ import annotations

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
    if len(sys.argv) < 2:
        print("usage: python scripts/proxmox/proxmox_exec.py <command>")
        return 2

    host = os.environ.get("PROXMOX_HOST", "192.168.50.9")
    user = os.environ.get("PROXMOX_USER", "root")
    key_path = os.environ.get("PROXMOX_KEY", DEFAULT_KEY_PATH)
    cmd = " ".join(sys.argv[1:])

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    key = load_private_key(key_path)
    client.connect(host, username=user, pkey=key, timeout=10)

    try:
        _stdin, stdout, stderr = client.exec_command(cmd, timeout=180)
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
