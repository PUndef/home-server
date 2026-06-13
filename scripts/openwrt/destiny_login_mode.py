"""Destiny login mode: Steam via awg2 for auth, then restore Steam WAN.

Usage:
  py -3 scripts/openwrt/destiny_login_mode.py login
  py -3 scripts/openwrt/destiny_login_mode.py login --full
  py -3 scripts/openwrt/destiny_login_mode.py normal
  py -3 scripts/openwrt/destiny_login_mode.py status
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import paramiko

SCRIPTS = Path(__file__).resolve().parent
LOGIN_SH = SCRIPTS / "destiny-login-mode.sh"
NORMAL_SH = SCRIPTS / "destiny-normal-mode.sh"
REMOTE_LOGIN = "/opt/destiny-login-mode.sh"
REMOTE_NORMAL = "/opt/destiny-normal-mode.sh"
FLAG = "/etc/destiny-login-mode"


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
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def upload_file(client: paramiko.SSHClient, local: Path, remote: str) -> None:
    import base64

    raw = local.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    data = base64.b64encode(raw).decode("ascii")
    cmd = f"base64 -d > {remote} && chmod 0755 {remote}"
    stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
    stdin.write(data)
    stdin.channel.shutdown_write()
    if stdout.channel.recv_exit_status() != 0:
        raise RuntimeError(stderr.read().decode("utf-8", errors="ignore") or f"upload failed: {remote}")


def steam_iface(client: paramiko.SSHClient) -> str:
    _, out = run_remote(
        client,
        "uci show pbr 2>/dev/null | grep \"name='pundef-pc steam\" | head -1; "
        "uci show pbr 2>/dev/null | awk -F= '/name=.pundef-pc steam/{print; exit}'",
    )
    if "destiny login" in out or "awg2" in out or "awg1" in out:
        if "wan" not in out.split("name=")[-1]:
            return "tunnel"
    _, iface = run_remote(
        client,
        "for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do "
        "n=$(uci -q get pbr.@policy[$i].name 2>/dev/null || true); "
        "case \"$n\" in 'pundef-pc steam via '*) uci -q get pbr.@policy[$i].interface; exit 0;; esac; "
        "done; echo unknown",
    )
    return iface.strip() or "unknown"


def verify_login(client: paramiko.SSHClient) -> list[str]:
    failures: list[str] = []
    _, flag = run_remote(client, f"test -f {FLAG} && echo on || echo off")
    if flag.strip() != "on":
        failures.append("login flag not set")

    _, flag_kind = run_remote(client, f"cat {FLAG} 2>/dev/null")
    if flag_kind.strip() == "full":
        _, nft = run_remote(
            client,
            "nft list chain inet fw4 pbr_prerouting 2>/dev/null | grep 'destiny login full' | head -1",
        )
        if "0.0.0.0/0" not in nft:
            failures.append(f"full catch-all missing in nft: {nft or 'empty'}")
    else:
        _, nft = run_remote(client, "nft list chain inet fw4 pbr_prerouting 2>/dev/null | grep 'steam via' | head -1")
        if "destiny login" not in nft and "awg2" not in nft and "awg1" not in nft:
            failures.append(f"steam policy not on tunnel in nft: {nft or 'missing'}")
        elif "pbr_mark_0x010000" in nft and "steam" in nft:
            failures.append("steam still marked for wan in nft")

    _, route2 = run_remote(
        client,
        "ip route get 104.17.101.21 mark 0x40000 2>&1 | head -1",
    )
    if "dev awg2" not in route2 and "dev awg1" not in route2:
        failures.append(f"bungie not via tunnel: {route2}")
    return failures


def verify_normal(client: paramiko.SSHClient) -> list[str]:
    failures: list[str] = []
    _, flag = run_remote(client, f"test -f {FLAG} && echo on || echo off")
    if flag.strip() == "on":
        failures.append("login flag still set")

    _, route = run_remote(
        client,
        "ip route get 23.61.239.50 from 192.168.1.133 iif br-lan mark 0x10000 2>&1 | head -1",
    )
    if " dev wan " not in route:
        failures.append(f"steam not via wan: {route}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description="Destiny login mode toggle")
    parser.add_argument("mode", choices=("login", "normal", "status"))
    parser.add_argument(
        "--full",
        action="store_true",
        help="Route all egress from gaming PC via tunnel (stronger TAPIR bypass)",
    )
    parser.add_argument(
        "--tunnel",
        choices=("awg2", "awg1"),
        default=None,
        help="Override tunnel for login (default: podkop primary)",
    )
    args = parser.parse_args()

    client = connect()
    try:
        upload_file(client, LOGIN_SH, REMOTE_LOGIN)
        upload_file(client, NORMAL_SH, REMOTE_NORMAL)

        if args.mode == "status":
            _, flag = run_remote(client, f"cat {FLAG} 2>/dev/null || echo normal")
            iface = steam_iface(client)
            _, full_rule = run_remote(
                client,
                "nft list chain inet fw4 pbr_prerouting 2>/dev/null | grep -c 'destiny login full' || true",
            )
            print(f"mode={flag.strip()} steam_policy_iface={iface} full_rule={full_rule.strip()}")
            return 0

        script = LOGIN_SH if args.mode == "login" else NORMAL_SH
        remote = REMOTE_LOGIN if args.mode == "login" else REMOTE_NORMAL
        body = script.read_text(encoding="utf-8")
        login_args = " --full" if args.full else ""
        env = ""
        if args.tunnel:
            env = f"PRIMARY={args.tunnel} "
        code, output = run_remote(
            client,
            f"{env}sh {remote}{login_args}",
            stdin_data=body,
        )
        print(output)
        if code != 0:
            return 1

        print("Waiting 20s for pbr...")
        time.sleep(20)

        failures = verify_login(client) if args.mode == "login" else verify_normal(client)
        if failures:
            print("VERIFY FAILED:")
            for f in failures:
                print(f"  - {f}")
            return 1

        if args.mode == "login":
            print("\n=== LOGIN MODE ===")
            print("1. Quit Steam fully (tray too)")
            print("2. Start Steam again")
            print("3. Launch Destiny 2")
            print("4. Play until you are IN THE WORLD (tower / ship / patrol) — NOT character select")
            print("5. Only then (or when done for the day):")
            print("   py -3 scripts/openwrt/destiny_login_mode.py normal")
            print("   (script pauses ~30-60s while pbr restarts — do not run during loading)")
        else:
            print("\n=== NORMAL MODE ===")
            print("Steam -> WAN again (fast downloads).")
            print("If Destiny is open, expect Weasel/disconnect — run only when idle or fully in-world.")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
