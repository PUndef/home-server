"""Safely enable Warframe/Soulframe routing via primary tunnel (router-resilience).

Usage:
  py -3 scripts/openwrt/enable_warframe_awg2_safe.py
  py -3 scripts/openwrt/enable_warframe_awg2_safe.py --dry-run
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parents[2]
ENABLE_SCRIPT = Path(__file__).resolve().parent / "enable-warframe-awg2.sh"
ROLLBACK_SCRIPT = Path(__file__).resolve().parent / "rollback-warframe-awg2.sh"
CHECK_STACK = ROOT / "scripts" / "openwrt" / "check_stack.py"

CRITICAL_CHECKS = [
    "default-route-wan",
    "dns-resolve-via-router",
    "wan-https-probe",
    "awg2-running",
    "pbr-awg2-table",
    "workvpn-running",
    "workvpn-policy-nft",
    "srv-zone-up",
    "nextcloud-https-direct",
    "proxmox-host-pveui-tcp",
    "haos-webui-tcp",
    "zapret-bypass-srv-postnat",
    "zapret-bypass-srv-prenat",
]


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


def run_remote(client: paramiko.SSHClient, command: str, stdin_data: str | None = None, timeout: int = 120) -> tuple[int, str]:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    if stdin_data is not None:
        stdin.write(stdin_data)
        stdin.channel.shutdown_write()
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    code = stdout.channel.recv_exit_status()
    return code, (out + ("\n" + err if err else "")).strip()


def run_check_stack() -> dict[str, bool]:
    proc = subprocess.run(
        [sys.executable, str(CHECK_STACK)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="ignore",
    )
    results: dict[str, bool] = {}
    for line in proc.stdout.splitlines():
        line = line.strip()
        if line.startswith("[OK"):
            name = line.split("]", 1)[1].strip().split()[0]
            results[name] = True
        elif line.startswith("[FAIL"):
            name = line.split("]", 1)[1].strip().split()[0]
            results[name] = False
    return results


def probe_srv_from_pc() -> list[str]:
    failures: list[str] = []
    for label, url in [
        ("proxmox", "https://192.168.50.9:8006/"),
        ("nextcloud", "https://192.168.50.34/"),
        ("haos", "http://192.168.50.51:8123/"),
    ]:
        proc = subprocess.run(
            ["curl", "-k", "-sS", "-o", "NUL", "-w", "%{http_code}", url],
            capture_output=True,
            text=True,
            shell=True,
        )
        if (proc.stdout.strip() or "000") == "000":
            failures.append(f"{label} ({url})")
    return failures


def verify_warframe_routing(client: paramiko.SSHClient) -> list[str]:
    failures: list[str] = []
    primary = "awg2"
    _, primary_out = run_remote(client, "uci -q get podkop.main.interface || echo awg2")
    if primary_out.strip() in ("awg1", "awg2"):
        primary = primary_out.strip()

    mark = "0x40000" if primary == "awg2" else "0x20000"
    checks = [
        (
            "warframe-policy-nft",
            f"nft list chain inet fw4 pbr_prerouting | grep -q 'Warframe via {primary}'",
        ),
        (
            "pundef-pc-games-policy-nft",
            f"nft list chain inet fw4 pbr_prerouting | grep -q 'pundef-pc games via {primary}'",
        ),
        (
            "warframe-route-mark",
            f"ip route get 88.221.97.74 mark {mark} 2>/dev/null | grep -q ' dev {primary} '",
        ),
        (
            "corp-workvpn-mark",
            "ip route get 10.0.17.5 mark 0x30000 2>/dev/null | grep -q 'dev vpn-workvpn'",
        ),
    ]
    for name, cmd in checks:
        code, out = run_remote(client, cmd)
        if code != 0:
            failures.append(f"{name}: {out or 'check failed'}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Safely enable Warframe via awg2")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    print("=== Baseline ===")
    before = run_check_stack()
    regress_pre = [n for n in CRITICAL_CHECKS if before.get(n) is False]
    if regress_pre:
        print("Pre-existing failures:", ", ".join(regress_pre))
    else:
        print("Baseline critical checks: OK")

    pc_before = probe_srv_from_pc()
    if pc_before:
        print("WARN: srv probes failed before change:", pc_before)
    else:
        print("Baseline srv probes: OK")

    if args.dry_run:
        return 0

    client = connect()
    try:
        print("\n=== Applying enable-warframe-awg2.sh ===")
        body = ENABLE_SCRIPT.read_text(encoding="utf-8")
        code, output = run_remote(client, "sh -s", stdin_data=body)
        print(output)
        if code != 0:
            return 1

        print("\n=== Waiting 25s ===")
        time.sleep(25)

        after = run_check_stack()
        stack_regress = [
            n for n in CRITICAL_CHECKS if before.get(n) is True and after.get(n) is False
        ]
        pc_after = probe_srv_from_pc()
        route_fail = verify_warframe_routing(client)

        if stack_regress or route_fail or (not pc_before and pc_after):
            print("REGRESSION — rolling back")
            for n in stack_regress:
                print(f"  check_stack: {n}")
            for f in route_fail:
                print(f"  routing: {f}")
            for p in pc_after:
                print(f"  srv: {p}")

            rb_body = ROLLBACK_SCRIPT.read_text(encoding="utf-8")
            rb_code, rb_out = run_remote(client, "sh -s", stdin_data=rb_body)
            print(rb_out)
            return 1 if rb_code != 0 else 1

        print("\n=== Success ===")
        print("Warframe/Soulframe: domains -> primary tunnel; pundef-pc (.133) all egress -> tunnel.")
        print("Test in-game chat; corp kpb.lt should still use workvpn on this PC.")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
