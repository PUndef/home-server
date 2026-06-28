"""One-time: allow SSH/LuCI from pundef-pc srv (.50.133) to the router.

Must run while on lan/Wi-Fi (192.168.1.x), not from Mercusys eth alone.

Usage:
  py -3 scripts/openwrt/enable_pundef_pc_srv_admin.py
"""

from __future__ import annotations

import os
import socket
import sys
from pathlib import Path

import paramiko
from paramiko.ssh_exception import NoValidConnectionsError

SCRIPT = Path(__file__).resolve().parent / "enable-pundef-pc-srv-admin.sh"


def load_private_key(key_path: str) -> paramiko.PKey:
    last_error: Exception | None = None
    for key_cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        try:
            return key_cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last_error = exc
    raise last_error or paramiko.SSHException("Unsupported private key type")


def local_on_srv() -> bool:
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            if info[4][0].startswith("192.168.50."):
                return True
    except OSError:
        pass
    return False


def main() -> int:
    if local_on_srv():
        print(
            "Сейчас uplink srv (192.168.50.x) — с него роутер не пускает в admin.\n"
            "Запусти этот скрипт с Mac (lan), Wi‑Fi или кабеля в lan3/lan4 X3000T.",
            file=sys.stderr,
        )
        return 2

    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    user = os.environ.get("OPENWRT_USER", "root")
    key_path = os.environ.get("OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(host, username=user, pkey=load_private_key(key_path), timeout=10)
    except NoValidConnectionsError as exc:
        print(f"SSH к {host} недоступен: {exc}", file=sys.stderr)
        return 1

    try:
        stdin, stdout, stderr = client.exec_command("sh -s", timeout=60)
        stdin.write(SCRIPT.read_text(encoding="utf-8"))
        stdin.channel.shutdown_write()
        out = stdout.read().decode("utf-8", errors="ignore")
        err = stderr.read().decode("utf-8", errors="ignore")
        code = stdout.channel.recv_exit_status()
        print(out + err)
        if code != 0:
            return code
        print("\nOK: с eth srv (192.168.50.133) теперь можно SSH на 192.168.50.1")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
