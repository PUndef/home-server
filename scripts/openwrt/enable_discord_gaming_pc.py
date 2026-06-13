"""Apply Discord DNS bypass on OpenWrt (fix fake-IP vs games catch-all).

Usage:
  py -3 scripts/openwrt/enable_discord_gaming_pc.py
"""

from __future__ import annotations

import os
import re
import sys
import time
from pathlib import Path

import paramiko

SCRIPT = Path(__file__).resolve().parent / "enable-discord-gaming-pc.sh"
FAKE_IP_RE = re.compile(r"^198\.18\.")


def load_private_key(key_path: str) -> paramiko.PKey:
    last_error: Exception | None = None
    for key_cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        try:
            return key_cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last_error = exc
    raise last_error or paramiko.SSHException("Unsupported private key type")


def connect() -> paramiko.SSHClient:
    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    user = os.environ.get("OPENWRT_USER", "root")
    key_path = os.environ.get("OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass")
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(host, username=user, pkey=load_private_key(key_path), timeout=10)
    return client


def run_remote(client: paramiko.SSHClient, command: str, stdin_data: str | None = None) -> tuple[int, str]:
    stdin, stdout, stderr = client.exec_command(command, timeout=120)
    if stdin_data is not None:
        stdin.write(stdin_data)
        stdin.channel.shutdown_write()
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def discord_ip(client: paramiko.SSHClient) -> str:
    _, out = run_remote(
        client,
        "nslookup discord.com 192.168.1.1 2>/dev/null | grep -E '^Address [0-9]' | tail -1 | awk '{print $3}'",
    )
    return out.strip()


def main() -> int:
    client = connect()
    try:
        before = discord_ip(client)
        print(f"discord.com before: {before or 'unresolved'}")

        code, output = run_remote(client, "sh -s", stdin_data=SCRIPT.read_text(encoding="utf-8"))
        print(output)
        if code != 0:
            return 1

        print("Waiting 15s...")
        time.sleep(15)

        after = discord_ip(client)
        print(f"discord.com after: {after or 'unresolved'}")
        if not after or FAKE_IP_RE.match(after):
            print("FAIL: Discord still resolves to podkop fake-IP")
            return 1

        code, probe = run_remote(
            client,
            "curl -4 -sS -o /dev/null -w '%{http_code}' --interface awg2 --connect-timeout 8 --max-time 12 https://discord.com/",
        )
        print(f"discord.com via awg2: HTTP {probe.strip()}")
        if code != 0 or probe.strip() not in ("200", "301", "302"):
            print("WARN: awg2 probe odd, but DNS fix applied — retry Discord client")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
