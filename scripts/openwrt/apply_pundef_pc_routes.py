"""Deploy and apply canonical pundef-pc routes — delegates to apply_overrides.py.

Usage:
  py -3 scripts/openwrt/apply_pundef_pc_routes.py
  py -3 scripts/openwrt/apply_pundef_pc_routes.py --install-cron

Prefer:
  py -3 scripts/openwrt/apply_overrides.py --mode normal
  py -3 scripts/openwrt/apply_overrides.py --install-cron
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
WATCHDOG_SH = SCRIPTS / "pundef-pc-routes-watchdog.sh"
REMOTE_WATCHDOG = "/opt/pundef-pc-routes-watchdog.sh"


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
    _stdin, stdout, stderr = client.exec_command(command, timeout=60)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def upload_file(client: paramiko.SSHClient, local: Path, remote: str, chmod: str = "0755") -> None:
    import base64

    raw = local.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    data = base64.b64encode(raw).decode("ascii")
    cmd = f"base64 -d > {remote} && chmod {chmod} {remote}"
    stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
    stdin.write(data)
    stdin.channel.shutdown_write()
    if stdout.channel.recv_exit_status() != 0:
        raise RuntimeError(stderr.read().decode("utf-8", errors="ignore") or f"upload failed: {remote}")


def install_cron(client: paramiko.SSHClient) -> None:
    upload_file(client, WATCHDOG_SH, REMOTE_WATCHDOG)
    cron_line = f"*/15 * * * * {REMOTE_WATCHDOG}"
    _, existing = run_remote(client, "cat /etc/crontabs/root 2>/dev/null || true")
    if "pundef-pc-routes-watchdog" in existing:
        print("cron watchdog already installed")
        return
    run_remote(client, f"(echo '{cron_line}') >> /etc/crontabs/root && /etc/init.d/cron restart")
    print("cron watchdog installed (every 15 min)")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply canonical pundef-pc routes")
    parser.add_argument("--install-cron", action="store_true", help="Install 15-min watchdog on router")
    parser.add_argument("--skip-check", action="store_true")
    parser.add_argument("--force-live-session", action="store_true")
    args = parser.parse_args()

    if args.install_cron:
        client = connect()
        try:
            install_cron(client)
        finally:
            client.close()

    cmd = [sys.executable, str(APPLY_OVERRIDES), "--mode", "normal"]
    if args.skip_check:
        cmd.append("--skip-check")
    if args.force_live_session:
        cmd.append("--force-live-session")

    print("Delegating to apply_overrides.py --mode normal")
    return subprocess.call(cmd, cwd=str(ROOT))


if __name__ == "__main__":
    raise SystemExit(main())
