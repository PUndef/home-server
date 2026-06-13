"""Steam via WAN for pundef-pc (fast CDN). Destiny — отдельная политика в apply-pundef-pc-routes.

Usage:
  py -3 scripts/openwrt/switch_steam_route.py wan
  py -3 scripts/openwrt/switch_steam_route.py status

Full gaming-PC state:
  py -3 scripts/openwrt/apply_pundef_pc_routes.py

Environment: OPENWRT_HOST, OPENWRT_USER, OPENWRT_KEY, STEAM_CLIENT_IP
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import paramiko

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = Path(__file__).resolve().parent
ROLLBACK_SCRIPT = SCRIPTS / "rollback-steam-wan.sh"
ENABLE_SCRIPT = SCRIPTS / "enable-steam-wan.sh"
CHECK_STEAM = SCRIPTS / "check_steam_route.py"

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


def run_remote(client: paramiko.SSHClient, command: str, stdin_data: str | None = None, timeout: int = 120) -> tuple[int, str]:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    if stdin_data is not None:
        stdin.write(stdin_data)
        stdin.channel.shutdown_write()
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    code = stdout.channel.recv_exit_status()
    return code, (out + ("\n" + err if err else "")).strip()


def current_mode(client: paramiko.SSHClient) -> str:
    for name in STEAM_POLICY_NAMES:
        code, _ = run_remote(client, f"uci show pbr 2>/dev/null | grep -q \"name='{name}'\"")
        if code == 0:
            return "wan"
    return "awg2"


def verify_mode(client: paramiko.SSHClient, expected: str, client_ip: str) -> list[str]:
    failures: list[str] = []
    mode = current_mode(client)
    if mode != expected:
        failures.append(f"uci mode is {mode}, expected {expected}")

    if expected == "wan":
        checks = [
            (
                "steam-policy-nft",
                "nft list chain inet fw4 pbr_prerouting | grep -q 'pundef-pc steam via wan'",
            ),
            (
                "steam-wan-route",
                f"ip route get 23.61.239.50 from {client_ip} iif br-lan mark 0x10000 2>/dev/null | grep -q ' dev wan '",
            ),
        ]
    else:
        checks = [
            (
                "no-steam-exception",
                "uci show pbr 2>/dev/null | grep -q \"name='pundef-pc steam via\" && exit 1 || exit 0",
            ),
            (
                "steam-via-games-catchall",
                f"ip route get 23.61.239.50 from {client_ip} iif br-lan mark 0x40000 2>/dev/null | grep -q ' dev awg2 '",
            ),
            (
                "games-catchall-nft",
                "nft list chain inet fw4 pbr_prerouting | grep -q 'pundef-pc games via awg2'",
            ),
        ]

    for name, cmd in checks:
        code, out = run_remote(client, cmd)
        if code != 0:
            failures.append(f"{name}: {out or 'check failed'}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Toggle Steam route: WAN vs awg2")
    parser.add_argument("mode", choices=("wan", "status", "awg2"), help="wan|status (awg2 deprecated)")
    parser.add_argument(
        "--client-ip",
        default=os.environ.get("STEAM_CLIENT_IP", "192.168.1.133"),
        help="LAN client IP (default: pundef-pc .133)",
    )
    parser.add_argument("--no-verify", action="store_true", help="Skip post-change routing checks")
    args = parser.parse_args()

    client = connect()
    try:
        if args.mode == "status":
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
            failures = verify_mode(client, mode, args.client_ip)
            if failures:
                print("WARN:", "; ".join(failures))
            return 0

        if args.mode == "awg2":
            print("awg2 mode removed (catch-all broke Discord/podkop).")
            print("Use: py -3 scripts/openwrt/apply_pundef_pc_routes.py")
            print("Destiny -> awg2 via 'pundef-pc destiny via awg2'; Steam stays WAN.")
            return 1

        before = current_mode(client)
        if before == args.mode:
            print(f"Already in mode {args.mode}; nothing to do.")
        else:
            print(f"Switching Steam route: {before} -> {args.mode}")
            script = ROLLBACK_SCRIPT if args.mode == "awg2" else ENABLE_SCRIPT
            body = script.read_text(encoding="utf-8")
            code, output = run_remote(client, "sh -s", stdin_data=body)
            print(output)
            if code != 0:
                return 1

            print("Waiting 20s for pbr nftset refill...")
            time.sleep(20)

        if args.no_verify:
            return 0

        failures = verify_mode(client, args.mode, args.client_ip)
        if failures:
            print("VERIFY FAILED:")
            for item in failures:
                print(f"  - {item}")
            return 1

        print("\n=== OK ===")
        print("Steam CDN/API from .133/.208 -> WAN (fast downloads).")
        print("Destiny -> awg2 via explicit policy (see gaming-pc-routes.md).")
        print(f"Check: py -3 {CHECK_STEAM.relative_to(ROOT)}")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
