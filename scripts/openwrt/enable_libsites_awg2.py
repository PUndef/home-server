"""Extend Mangalib pbr policy with all Lib-family domains (egress via primary AWG tunnel).

Usage:
  py -3 scripts/openwrt/enable_libsites_awg2.py
"""

from __future__ import annotations

import os
import re
import socket
import sys
import time
from pathlib import Path

import paramiko
from paramiko.ssh_exception import NoValidConnectionsError

SCRIPT = Path(__file__).resolve().parent / "enable-libsites-awg2.sh"
FAKE_IP_RE = re.compile(r"^198\.18\.")

# Spot-check: different backends (ddos-guard direct, cloudflare, lib.social).
VERIFY_HOSTS = (
    "v5.animelib.org",
    "hentailib.me",
    "mangalib.me",
    "v2.shlib.life",
    "lib.social",
)


def local_ipv4_addrs() -> list[str]:
    addrs: list[str] = []
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if not ip.startswith("127."):
                addrs.append(ip)
    except OSError:
        pass
    return sorted(set(addrs))


def srv_admin_hint() -> str:
    ips = local_ipv4_addrs()
    on_srv = any(ip.startswith("192.168.50.") for ip in ips)
    if not on_srv:
        return ""
    return (
        "\n\nТы на srv (Mercusys, 192.168.50.133): роутер режет SSH/LuCI с lan2 — это не баг скрипта.\n"
        "Варианты:\n"
        "  1) Один раз с Mac/Wi‑Fi: py -3 scripts/openwrt/enable_pundef_pc_srv_admin.py\n"
        "  2) Кабель в lan3/lan4 X3000T или Wi‑Fi 192.168.1.x\n"
        "  3) С Mac: ssh root@192.168.1.1 'sh -s' < scripts/openwrt/enable-libsites-awg2.sh"
    )


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
    try:
        client.connect(host, username=user, pkey=load_private_key(key_path), timeout=10)
    except NoValidConnectionsError as exc:
        hint = srv_admin_hint()
        raise SystemExit(
            f"SSH к {host}:22 недоступен с этой машины ({', '.join(local_ipv4_addrs()) or 'no IP'}). "
            f"{exc}{hint}"
        ) from exc
    return client


def run_remote(client: paramiko.SSHClient, command: str, stdin_data: str | None = None) -> tuple[int, str]:
    stdin, stdout, stderr = client.exec_command(command, timeout=120)
    if stdin_data is not None:
        stdin.write(stdin_data)
        stdin.channel.shutdown_write()
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def resolve(client: paramiko.SSHClient, host: str) -> str:
    _, out = run_remote(
        client,
        f"nslookup {host} 192.168.1.1 2>/dev/null | grep -E '^Address [0-9]' | tail -1 | awk '{{print $3}}'",
    )
    return out.strip()


def main() -> int:
    client = connect()
    try:
        primary, _ = run_remote(client, "uci -q get podkop.main.interface || echo awg2")
        primary = primary.strip() or "awg2"
        policy_name = f"Mangalib via {primary}"

        for host in VERIFY_HOSTS:
            print(f"{host} before: {resolve(client, host) or 'unresolved'}")

        code, output = run_remote(client, "sh -s", stdin_data=SCRIPT.read_text(encoding="utf-8"))
        print(output)
        if code != 0:
            return 1

        print("Waiting 15s...")
        time.sleep(15)

        failed: list[str] = []
        for host in VERIFY_HOSTS:
            ip = resolve(client, host)
            print(f"{host} after: {ip or 'unresolved'}")
            if not ip or FAKE_IP_RE.match(ip):
                failed.append(host)

        if failed:
            print(f"FAIL: still fake-IP or unresolved: {', '.join(failed)}")
            return 1

        for domain in ("hentailib.me", "animelib.org", "mangalib.org", "shlib.life"):
            _, check = run_remote(
                client,
                f"uci show pbr 2>/dev/null | grep -E \"dest_addr='{domain}'\" | head -1",
            )
            if not check.strip():
                print(f"FAIL: {domain} missing from pbr dest_addr")
                return 1
        _, wan_check = run_remote(
            client,
            "uci show pbr 2>/dev/null | grep -E \"dest_addr='v5.animelib.org'\" | head -1",
        )
        if not wan_check.strip():
            print("FAIL: v5.animelib.org missing from WAN pbr policy")
            return 1
        print(f"[OK] policy: {policy_name} + Lib DDG mirrors via wan")

        for host in ("v5.animelib.org", "hentailib.me"):
            code, probe = run_remote(
                client,
                f"curl -4 -sS -o /dev/null -w '%{{http_code}}' --interface {primary} "
                f"--connect-timeout 8 --max-time 12 https://{host}/",
            )
            print(f"{host} via {primary}: HTTP {probe.strip()}")
            if code != 0 or probe.strip() not in ("200", "301", "302", "403", "404"):
                print(f"WARN: {host} probe odd — policy applied, retry in browser")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
