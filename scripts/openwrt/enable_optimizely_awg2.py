"""Apply Optimizely pbr + DNS bypass on OpenWrt (egress via primary AWG tunnel).

Usage:
  py -3 scripts/openwrt/enable_optimizely_awg2.py
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

SCRIPT = Path(__file__).resolve().parent / "enable-optimizely-awg2.sh"
FAKE_IP_RE = re.compile(r"^198\.18\.")


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
        "     (потом deploy с eth srv заработает)\n"
        "  2) Кабель в lan3/lan4 X3000T или Wi‑Fi 192.168.1.x\n"
        "  3) С Mac: ssh root@192.168.1.1 'sh -s' < scripts/openwrt/enable-optimizely-awg2.sh"
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

        before = resolve(client, "cdn.optimizely.com")
        print(f"cdn.optimizely.com before: {before or 'unresolved'}")

        code, output = run_remote(client, "sh -s", stdin_data=SCRIPT.read_text(encoding="utf-8"))
        print(output)
        if code != 0:
            return 1

        print("Waiting 15s...")
        time.sleep(15)

        after = resolve(client, "cdn.optimizely.com")
        print(f"cdn.optimizely.com after: {after or 'unresolved'}")
        if not after or FAKE_IP_RE.match(after):
            print("FAIL: Optimizely CDN still resolves to podkop fake-IP")
            return 1

        _, policy = run_remote(
            client,
            f"uci show pbr 2>/dev/null | grep -q \"name='Optimizely via {primary}'\" && echo ok || echo missing",
        )
        if policy.strip() != "ok":
            print(f"FAIL: missing pbr policy Optimizely via {primary}")
            return 1
        print(f"[OK] policy: Optimizely via {primary}")

        code, probe = run_remote(
            client,
            f"curl -4 -sS -o /dev/null -w '%{{http_code}}' --interface {primary} "
            "--connect-timeout 8 --max-time 12 https://cdn.optimizely.com/",
        )
        print(f"cdn.optimizely.com via {primary}: HTTP {probe.strip()}")
        if code != 0 or probe.strip() not in ("200", "301", "302", "403", "404"):
            print("WARN: awg probe odd — policy applied, retry from browser")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
