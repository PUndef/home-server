"""Add split-horizon DNS for static-sites hostnames on OpenWrt."""
from __future__ import annotations

import os
import sys

import paramiko

HOST = os.environ.get("OPENWRT_HOST", "192.168.1.1")
KEY = os.environ.get("OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass")
HOSTNAMES = ("network.home",)


def load_key(key_path: str) -> paramiko.PKey:
    last: Exception | None = None
    for cls in (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey):
        try:
            return cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last = exc
    raise last or paramiko.SSHException("unsupported key")


def run(client: paramiko.SSHClient, cmd: str) -> str:
    _stdin, stdout, stderr = client.exec_command(cmd, timeout=30)
    return (stdout.read() + stderr.read()).decode("utf-8", errors="ignore")


def main() -> int:
    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(HOST, username="root", pkey=load_key(KEY), timeout=10)
    try:
        changed = False
        for name in HOSTNAMES:
            entry = f"/{name}/192.168.50.35"
            if name in run(client, "uci show dhcp.@dnsmasq[0].server 2>/dev/null"):
                print(f"[OK] {entry} already present")
                continue
            run(client, f"uci add_list dhcp.@dnsmasq[0].server={entry}")
            print(f"[ADD] {entry}")
            changed = True
        if changed:
            run(client, "uci commit dhcp")
            run(client, "/etc/init.d/dnsmasq restart")
            print("dnsmasq restarted")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
