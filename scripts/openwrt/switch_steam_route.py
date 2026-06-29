"""DEPRECATED: use apply_overrides.py for Steam WAN baseline.

Usage:
  py -3 scripts/openwrt/switch_steam_route.py wan     # delegates to apply_overrides --mode normal
  py -3 scripts/openwrt/switch_steam_route.py status  # read-only

Prefer:
  py -3 scripts/openwrt/apply_overrides.py --mode normal
  py -3 scripts/openwrt/check_gaming_pc_routes.py
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = Path(__file__).resolve().parent
APPLY_OVERRIDES = SCRIPTS / "apply_overrides.py"

STEAM_POLICY_NAMES = (
    "pundef-pc steam via wan",
    "pundef-pc steam via awg1",
    "pundef-pc steam via awg2",
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
    client.connect(host, username=user, pkey=load_private_key(key_path), timeout=10)
    return client


def run_remote(client: paramiko.SSHClient, command: str) -> tuple[int, str]:
    _stdin, stdout, stderr = client.exec_command(command, timeout=120)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def current_mode(client: paramiko.SSHClient) -> str:
    for name in STEAM_POLICY_NAMES:
        code, _ = run_remote(client, f"uci show pbr 2>/dev/null | grep -q \"name='{name}'\"")
        if code == 0:
            return "wan"
    return "awg2"


def main() -> int:
    parser = argparse.ArgumentParser(description="DEPRECATED Steam route helper")
    parser.add_argument("mode", choices=("wan", "status", "awg2"), help="wan|status (awg2 removed)")
    parser.add_argument(
        "--client-ip",
        default=os.environ.get("STEAM_CLIENT_IP", "192.168.1.133"),
        help="Unused; kept for CLI compatibility",
    )
    parser.add_argument("--no-verify", action="store_true", help="Passed through to apply_overrides")
    args = parser.parse_args()

    if args.mode == "awg2":
        print("awg2 mode removed (catch-all broke Discord/podkop).")
        print("Use: py -3 scripts/openwrt/apply_overrides.py --mode normal")
        return 1

    if args.mode == "wan":
        print("DEPRECATED: delegating to apply_overrides.py --mode normal")
        cmd = [sys.executable, str(APPLY_OVERRIDES), "--mode", "normal"]
        if args.no_verify:
            cmd.append("--skip-check")
        return subprocess.call(cmd, cwd=str(ROOT))

    client = connect()
    try:
        mode = current_mode(client)
        _, primary = run_remote(client, "uci -q get podkop.main.interface || echo awg2")
        primary = primary.strip() or "awg2"
        if mode == "wan":
            _, names = run_remote(
                client,
                "uci show pbr 2>/dev/null | grep \"name='pundef-pc steam via\" | head -1",
            )
            print(f"steam=wan ({names})")
        else:
            print("steam=no explicit WAN policy (uses podkop/default)")
        print(f"destiny -> {primary} (explicit policy); see gaming-pc-routes.md")
        print("Prefer: py -3 scripts/openwrt/check_gaming_pc_routes.py")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
