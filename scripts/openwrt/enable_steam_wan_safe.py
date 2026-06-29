"""DEPRECATED: use apply_overrides.py --mode normal.

Safely enable Steam via WAN for pundef-pc (router-resilience legacy wrapper).

Usage:
  py -3 scripts/openwrt/enable_steam_wan_safe.py   # delegates to apply_overrides.py
  py -3 scripts/openwrt/enable_steam_wan_safe.py --legacy  # old check_stack path

Prefer:
  py -3 scripts/openwrt/apply_overrides.py --mode normal
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
APPLY_OVERRIDES = Path(__file__).resolve().parent / "apply_overrides.py"
ENABLE_SCRIPT = Path(__file__).resolve().parent / "enable-steam-wan.sh"
ROLLBACK_SCRIPT = Path(__file__).resolve().parent / "rollback-steam-wan.sh"
RESTORE_AI_SCRIPT = Path(__file__).resolve().parent / "restore-ai-tools-pbr.sh"
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


def verify_steam_routing(client: paramiko.SSHClient) -> list[str]:
    failures: list[str] = []
    checks = [
        (
            "ai-tools-policy-nft",
            "nft list chain inet fw4 pbr_prerouting | grep -q 'AI Tools via awg2'",
        ),
        (
            "steam-policy-nft",
            "nft list chain inet fw4 pbr_prerouting | grep -q 'pundef-pc steam via wan'",
        ),
        (
            "steam-before-games",
            r"nft list chain inet fw4 pbr_prerouting | awk "
            r"'/pundef-pc steam via wan/{s=NR} /pundef-pc games via/{g=NR} END{exit !(s && g && s<g)}'",
        ),
        (
            "steam-resolve",
            "nslookup store.steampowered.com 192.168.1.1 | grep -qE 'Address.*: [0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+'",
        ),
        (
            "steam-wan-mark-route",
            "ip route get 23.61.239.50 mark 0x10000 2>/dev/null | grep -q ' dev wan '",
        ),
        (
            "corp-workvpn-mark",
            "ip route get 10.0.17.5 mark 0x30000 2>/dev/null | grep -q 'dev vpn-workvpn'",
        ),
        (
            "games-catchall-still-awg2",
            "nft list chain inet fw4 pbr_prerouting | grep -q 'pundef-pc games via awg2'",
        ),
    ]
    for name, cmd in checks:
        code, out = run_remote(client, cmd)
        if code != 0:
            failures.append(f"{name}: {out or 'check failed'}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="DEPRECATED: use apply_overrides.py --mode normal")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--legacy", action="store_true", help="Run old check_stack + enable-steam-wan path")
    args = parser.parse_args()

    if not args.legacy and not args.dry_run:
        print("DEPRECATED: delegating to apply_overrides.py --mode normal")
        return subprocess.call([sys.executable, str(APPLY_OVERRIDES), "--mode", "normal"], cwd=str(ROOT))

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
        print("\n=== Restoring AI Tools policy if missing ===")
        restore_body = RESTORE_AI_SCRIPT.read_text(encoding="utf-8")
        code0, output0 = run_remote(client, "sh -s", stdin_data=restore_body)
        print(output0)
        if code0 != 0:
            return 1

        print("\n=== Applying enable-steam-wan.sh ===")
        body = ENABLE_SCRIPT.read_text(encoding="utf-8")
        code, output = run_remote(client, "sh -s", stdin_data=body)
        print(output)
        if code != 0:
            return 1

        print("\n=== Waiting 25s (pbr nftset refill) ===")
        time.sleep(25)

        after = run_check_stack()
        stack_regress = [
            n for n in CRITICAL_CHECKS if before.get(n) is True and after.get(n) is False
        ]
        pc_after = probe_srv_from_pc()
        route_fail = verify_steam_routing(client)

        if stack_regress or route_fail or (not pc_before and pc_after):
            print("REGRESSION - rolling back")
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
        print("Steam (*.steampowered.com, CDN) from pundef-pc (.133) -> WAN.")
        print("Warframe and other egress on this PC still -> awg2 (games catch-all).")
        print("Verify: py -3 scripts/openwrt/check_steam_route.py --benchmark")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
