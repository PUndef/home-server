"""Safely switch primary VPN tunnel (awg1 Fin <-> awg2 Neth) on OpenWrt.

Protocol: baseline check_stack -> apply switch-primary-tunnel.sh -> wait -> verify
-> auto-rollback to previous primary on regression.

Usage:
  py -3 scripts/openwrt/switch_primary_tunnel_safe.py awg2
  py -3 scripts/openwrt/switch_primary_tunnel_safe.py awg1 --dry-run
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
SWITCH_SCRIPT = Path(__file__).resolve().parent / "switch-primary-tunnel.sh"
CHECK_STACK = ROOT / "scripts" / "openwrt" / "check_stack.py"

PC_SRV_TARGETS = [
    ("proxmox", "https://192.168.50.9:8006/"),
    ("nextcloud", "https://192.168.50.34/"),
]


def critical_checks_for(primary: str) -> list[str]:
    base = [
        "default-route-wan",
        "dns-resolve-via-router",
        "wan-https-probe",
        "podkop-enabled",
        "sing-box-running",
        "pbr-policy-nft",
        "pbr-mark-route-test",
        "srv-zone-up",
        "srv-vms-reachable",
        "vm-isolation-from-tunnels",
        "nextcloud-https-direct",
        "proxmox-host-pveui-tcp",
        "zapret-bypass-srv-postnat",
        "zapret-bypass-srv-prenat",
    ]
    if primary == "awg2":
        base.insert(8, "awg2-egress-probe")
    return base


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


def run_remote(client: paramiko.SSHClient, command: str, stdin_data: str | None = None, timeout: int = 180) -> tuple[int, str]:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    if stdin_data is not None:
        stdin.write(stdin_data)
        stdin.channel.shutdown_write()
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    code = stdout.channel.recv_exit_status()
    combined = (out + ("\n" + err if err else "")).strip()
    return code, combined


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
    for label, url in PC_SRV_TARGETS:
        proc = subprocess.run(
            ["curl", "-k", "-sS", "-o", "NUL", "-w", "%{http_code}", url],
            capture_output=True,
            text=True,
            shell=True,
        )
        code = proc.stdout.strip() or "000"
        if code == "000":
            failures.append(f"{label} ({url}) -> {code}")
    return failures


def get_current_primary(client: paramiko.SSHClient) -> str:
    _, out = run_remote(client, "uci -q get podkop.main.interface")
    primary = out.strip()
    if primary not in ("awg1", "awg2"):
        raise RuntimeError(f"Unexpected podkop.main.interface: {primary!r}")
    return primary


def main() -> int:
    parser = argparse.ArgumentParser(description="Safely switch primary awg tunnel on OpenWrt")
    parser.add_argument("target", choices=("awg1", "awg2"), help="New primary tunnel")
    parser.add_argument("--dry-run", action="store_true", help="Baseline only, no changes")
    args = parser.parse_args()

    critical = critical_checks_for(args.target)

    print("=== Baseline ===")
    before = run_check_stack()
    before_failures = [n for n in critical if before.get(n) is False]
    if before_failures:
        print("Pre-existing critical failures:")
        for name in before_failures:
            print(f"  - {name}")
    else:
        print("Baseline critical checks: all green")

    pc_before = probe_srv_from_pc()
    if pc_before:
        for item in pc_before:
            print(f"  PC probe FAIL: {item}")

    client = connect()
    try:
        current = get_current_primary(client)
        print(f"Current primary: {current} -> target: {args.target}")

        if current == args.target:
            print("Already on target tunnel; nothing to do.")
            return 0

        if args.dry_run:
            print("Dry-run: stopping before apply.")
            return 0

        if not SWITCH_SCRIPT.is_file():
            print(f"Missing: {SWITCH_SCRIPT}")
            return 2

        print("\n=== Applying switch-primary-tunnel.sh ===")
        code, output = run_remote(
            client,
            f"sh -s {args.target}",
            stdin_data=SWITCH_SCRIPT.read_text(encoding="utf-8"),
        )
        print(output)
        if code != 0:
            print(f"Apply failed (exit {code})")
            return 1

        print("\n=== Waiting 45s for stack to settle ===")
        time.sleep(45)

        print("=== Post-apply verification ===")
        after = run_check_stack()
        regressions = [n for n in critical if before.get(n) is True and after.get(n) is False]
        pc_after = probe_srv_from_pc()
        pc_regressions = [x for x in pc_after if x not in pc_before]

        if regressions or pc_regressions:
            print("REGRESSION — rolling back to", current)
            for name in regressions:
                print(f"  - check_stack: {name}")
            for item in pc_regressions:
                print(f"  - PC: {item}")
            rb_code, rb_out = run_remote(
                client,
                f"sh -s {current}",
                stdin_data=SWITCH_SCRIPT.read_text(encoding="utf-8"),
            )
            print(rb_out)
            time.sleep(30)
            return 1 if rb_code != 0 else 1

        verify_primary, _ = run_remote(client, "uci -q get podkop.main.interface")
        print(f"Verified podkop.main.interface={verify_primary.strip()}")
        print("\n=== Success ===")
        print(f"Primary tunnel is now {args.target}. Re-run: py scripts/openwrt/check_stack.py")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
