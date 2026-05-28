"""Safely enable workvpn corp routing for a LAN client (router-resilience protocol).

Runs baseline probes, applies enable-workvpn-client.sh on OpenWrt, waits for the
stack to settle, verifies critical paths, and auto-rolls back on regression.

Usage:
  py -3 scripts/openwrt/enable_workvpn_client_safe.py
  py -3 scripts/openwrt/enable_workvpn_client_safe.py --dry-run
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
ENABLE_SCRIPT = Path(__file__).resolve().parent / "enable-workvpn-client.sh"
ROLLBACK_SCRIPT = Path(__file__).resolve().parent / "rollback-workvpn-xiaomi-13t-pro.sh"
CHECK_STACK = ROOT / "scripts" / "openwrt" / "check_stack.py"

# Probes that must stay green; see docs/network/router-resilience.md
CRITICAL_CHECKS = [
    "default-route-wan",
    "dns-resolve-via-router",
    "wan-https-probe",
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
    py = sys.executable
    proc = subprocess.run(
        [py, str(CHECK_STACK)],
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
    targets = [
        ("proxmox", "https://192.168.50.9:8006/"),
        ("nextcloud", "https://192.168.50.34/"),
        ("haos", "http://192.168.50.51:8123/"),
    ]
    for label, url in targets:
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


def main() -> int:
    parser = argparse.ArgumentParser(description="Safely enable workvpn for a LAN client")
    parser.add_argument("--dry-run", action="store_true", help="Only run baseline checks")
    args = parser.parse_args()

    print("=== Baseline (router-resilience protocol) ===")
    before = run_check_stack()
    missing = [name for name in CRITICAL_CHECKS if name not in before]
    if missing:
        print(f"WARN: check_stack missing probes: {', '.join(missing)}")

    before_failures = [name for name in CRITICAL_CHECKS if before.get(name) is False]
    if before_failures:
        print("Baseline critical failures (pre-existing):")
        for name in before_failures:
            print(f"  - {name}")
    else:
        print("Baseline critical checks: all green")

    pc_before = probe_srv_from_pc()
    if pc_before:
        print("Baseline PC srv probes failed:")
        for item in pc_before:
            print(f"  - {item}")
    else:
        print("Baseline PC srv probes: OK")

    if args.dry_run:
        print("Dry-run: stopping before apply.")
        return 0

    if not ENABLE_SCRIPT.is_file():
        print(f"Missing script: {ENABLE_SCRIPT}")
        return 2

    client = connect()
    try:
        print("\n=== Applying enable-workvpn-client.sh ===")
        script_body = ENABLE_SCRIPT.read_text(encoding="utf-8")
        code, output = run_remote(client, "sh -s", stdin_data=script_body)
        print(output)
        if code != 0:
            print(f"Apply failed with exit code {code}")
            return 1

        print("\n=== Waiting 30s for pbr/firewall to settle ===")
        time.sleep(30)

        print("=== Post-apply verification ===")
        after = run_check_stack()
        regressions = [
            name
            for name in CRITICAL_CHECKS
            if before.get(name) is True and after.get(name) is False
        ]
        pc_after = probe_srv_from_pc()
        pc_regressions = [item for item in pc_after if item not in pc_before]

        if regressions or pc_regressions:
            print("REGRESSION detected — rolling back xiaomi workvpn rules:")
            for name in regressions:
                print(f"  - check_stack: {name}")
            for item in pc_regressions:
                print(f"  - PC probe: {item}")

            rollback_body = ROLLBACK_SCRIPT.read_text(encoding="utf-8")
            rb_code, rb_out = run_remote(client, "sh -s", stdin_data=rollback_body)
            print(rb_out)
            if rb_code != 0:
                print(f"Rollback script exit code {rb_code} — check router manually")
                return 1
            print("Rollback completed. Home LAN/srv should match pre-change state.")
            return 1

        # Confirm xiaomi policy exists
        _, verify = run_remote(
            client,
            "uci show pbr | grep -F 'xiaomi-13t-pro kpb via workvpn' && "
            "nft list chain inet fw4 pbr_prerouting | grep -F 'xiaomi-13t-pro kpb via workvpn'",
        )
        print(verify or "(verify output empty — inspect pbr manually)")

        print("\n=== Success ===")
        print("Corp routing enabled for xiaomi-13t-pro (192.168.1.204).")
        print("On phone: Private DNS OFF, Wi-Fi MAC randomization OFF, reconnect Wi-Fi.")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
