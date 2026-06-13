"""Deploy and apply canonical pundef-pc routes (no catch-all).

Usage:
  py -3 scripts/openwrt/apply_pundef_pc_routes.py
  py -3 scripts/openwrt/apply_pundef_pc_routes.py --install-cron
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
SCRIPTS = Path(__file__).resolve().parent
APPLY_SH = SCRIPTS / "apply-pundef-pc-routes.sh"
WATCHDOG_SH = SCRIPTS / "pundef-pc-routes-watchdog.sh"
CHECK = SCRIPTS / "check_gaming_pc_routes.py"
REMOTE_APPLY = "/opt/apply-pundef-pc-routes.sh"
REMOTE_WATCHDOG = "/opt/pundef-pc-routes-watchdog.sh"
HOTPLUG_LOCAL = SCRIPTS / "99-vpn-stack"
REMOTE_HOTPLUG = "/etc/hotplug.d/iface/99-vpn-stack"


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


def upload_file(client: paramiko.SSHClient, local: Path, remote: str, chmod: str = "0755") -> None:
    import base64

    raw = local.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    data = base64.b64encode(raw).decode("ascii")
    cmd = f"base64 -d > {remote} && chmod {chmod} {remote} && wc -c {remote}"
    stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
    stdin.write(data)
    stdin.channel.shutdown_write()
    code = stdout.channel.recv_exit_status()
    if code != 0:
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
    args = parser.parse_args()

    client = connect()
    try:
        print("Uploading scripts to router...")
        upload_file(client, APPLY_SH, REMOTE_APPLY)
        if HOTPLUG_LOCAL.exists():
            upload_file(client, HOTPLUG_LOCAL, REMOTE_HOTPLUG)

        if args.install_cron:
            install_cron(client)

        _, login_flag = run_remote(client, "test -f /etc/destiny-login-mode && echo login || echo normal")
        if login_flag.strip() == "login":
            print("Destiny login mode active — skip apply (run destiny_login_mode.py normal first)")
            return 0

        print("Applying routes...")
        code, output = run_remote(client, f"sh {REMOTE_APPLY}")
        print(output)
        if code != 0:
            return 1

        print("Waiting 20s for pbr/dnsmasq settle...")
        time.sleep(20)

        verify_code, verify_out = run_remote(client, f"sh {REMOTE_APPLY} --check-only")
        print(verify_out)
        if verify_code != 0:
            print("VERIFY FAILED after apply")
            return 1

        if not args.skip_check and CHECK.exists():
            print("\n=== check_gaming_pc_routes ===")
            proc = subprocess.run([sys.executable, str(CHECK)], cwd=str(ROOT))
            if proc.returncode != 0:
                return proc.returncode

        print("\n=== OK ===")
        print("Catch-all removed. Routes will self-heal via 99-vpn-stack + cron watchdog.")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
