"""Verify pundef-pc routing: no catch-all, explicit policies, DNS bypasses.

Usage:
  py -3 scripts/openwrt/check_gaming_pc_routes.py
"""

from __future__ import annotations

import os
import re
import sys

import paramiko

FAKE_IP = re.compile(r"^198\.18\.")

CLIENTS = ("192.168.1.133", "192.168.1.208")


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


def run(client: paramiko.SSHClient, cmd: str) -> tuple[int, str]:
    _stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def resolve(client: paramiko.SSHClient, host: str) -> str:
    code, out = run(client, f"nslookup {host} 192.168.1.1 2>/dev/null")
    if code != 0:
        return ""
    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("Address"):
            continue
        # "Address 1: 192.168.1.1" or "Address: 162.159.x.x"
        parts = line.split(":", 1)
        if len(parts) < 2:
            continue
        ip = parts[1].strip().split()[0]
        if not ip or ip == "192.168.1.1" or ip.endswith(":53"):
            continue
        if ":" in ip:
            continue  # prefer IPv4 for route checks
        return ip
    return ""


def main() -> int:
    client = connect()
    failures: list[str] = []
    try:
        _, primary = run(client, "uci -q get podkop.main.interface || echo awg2")
        primary = primary.strip() or "awg2"

        print(f"pundef-pc route check | primary={primary}")

        code, nft = run(client, "nft list chain inet fw4 pbr_prerouting 2>/dev/null")
        if code != 0:
            failures.append("pbr_prerouting unreadable")
        elif "0.0.0.0/0" in nft and "games via" in nft:
            failures.append("catch-all 0.0.0.0/0 still in nft (games policy)")
        else:
            print("[OK] no catch-all in nft")

        for policy in (
            "pundef-pc steam via wan",
            "pundef-pc nexus via wan",
            f"pundef-pc destiny via {primary}",
            f"Warframe via {primary}",
        ):
            code, _ = run(client, f"uci show pbr 2>/dev/null | grep -q \"name='{policy}'\"")
            if code == 0:
                print(f"[OK] policy: {policy}")
            else:
                failures.append(f"missing policy: {policy}")

        # Destiny auth domains may have no public A record; pbr matches by name via nftset fill.
        DESTINY_NO_A = frozenset({"steamserver.net", "deadorbit.net", "gravityshavings.net"})

        for host in ("discord.com", "bungie.net", "store.steampowered.com"):
            ip = resolve(client, host)
            if not ip:
                failures.append(f"dns: {host} unresolved")
            elif FAKE_IP.match(ip):
                failures.append(f"dns: {host} -> fake-IP {ip} (need bypass)")
            else:
                print(f"[OK] dns: {host} -> {ip}")

        _, destiny_dest = run(client, "uci show pbr 2>/dev/null | grep -E 'dest_addr=.*destiny|steamserver|deadorbit|gravityshavings' || uci show pbr 2>/dev/null | grep -E 'steamserver|deadorbit|gravityshavings'")
        for host in DESTINY_NO_A:
            if host in destiny_dest:
                print(f"[OK] destiny policy lists {host} (no public A — OK)")
            else:
                failures.append(f"destiny policy missing domain: {host}")

        for client_ip in CLIENTS:
            code, route = run(
                client,
                f"ip route get 23.61.239.50 from {client_ip} iif br-lan mark 0x10000 2>/dev/null | head -1",
            )
            if code == 0 and " dev wan " in route:
                print(f"[OK] steam path {client_ip} -> wan")
            else:
                failures.append(f"steam path {client_ip}: {route or 'fail'}")

        if "pundef-pc destiny via" in nft:
            print("[OK] destiny nft rule for .133/.208")
        bungie_ip = resolve(client, "bungie.net")
        if bungie_ip and not FAKE_IP.match(bungie_ip):
            _, route = run(client, f"ip route get {bungie_ip} mark 0x40000 2>&1 | head -1")
            if f"dev {primary}" in route:
                print(f"[OK] destiny mark route -> {primary}")
            else:
                failures.append(f"destiny mark route: {route or 'empty'}")

        code, out = run(client, "sh /opt/apply-pundef-pc-routes.sh --check-only 2>/dev/null")
        if code == 0:
            print("[OK] apply script --check-only")
        else:
            failures.append(f"apply --check-only failed: {out[:200]}")

    finally:
        client.close()

    print()
    if failures:
        print(f"FAILED ({len(failures)}):")
        for item in failures:
            print(f"  - {item}")
        print("Fix: py -3 scripts/openwrt/apply_pundef_pc_routes.py")
        return 1

    print("All gaming-PC route checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
