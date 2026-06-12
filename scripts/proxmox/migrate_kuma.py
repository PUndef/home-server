#!/usr/bin/env python3
"""Migrate Uptime Kuma phoneserver -> static-sites LXC. Short timeouts, no heredocs."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PHONE_IP = os.environ.get("PHONE_IP", "192.168.1.227")
LXC_VMID = os.environ.get("LXC_VMID", "102")
KUMA_VERSION = os.environ.get("KUMA_VERSION", "2.3.2")
WSL_KEY = os.path.expanduser("~/.ssh/phoneserver_nopass")
WIN_TMP = Path(os.environ.get("TEMP", tempfile.gettempdir())) / "kuma-backup.db"
WIN_TMP_WSL = (
    "/mnt/c"
    + Path(os.environ.get("TEMP", tempfile.gettempdir())).as_posix().split(":", 1)[-1]
    + "/kuma-backup.db"
)


def wsl_bash(script: str, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["wsl", "bash", "-lc", script],
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def phone(cmd: str, timeout: int = 90) -> subprocess.CompletedProcess[str]:
    remote = f"pmos@{PHONE_IP}"
    return wsl_bash(
        f"ssh -o StrictHostKeyChecking=no -o ConnectTimeout=12 "
        f"-o ServerAliveInterval=10 -o ServerAliveCountMax=3 "
        f"-i {WSL_KEY} {remote} {cmd!r}",
        timeout=timeout,
    )


def proxmox(cmd: str, timeout: int = 600) -> subprocess.CompletedProcess[str]:
    script = REPO / "scripts" / "proxmox" / "proxmox_exec.py"
    return subprocess.run(
        [sys.executable, str(script), cmd],
        capture_output=True,
        text=True,
        timeout=timeout,
        cwd=REPO,
    )


def upload(local: Path, remote: str, chmod: str = "") -> subprocess.CompletedProcess[str]:
    script = REPO / "scripts" / "proxmox" / "upload.py"
    args = [sys.executable, str(script), str(local), remote]
    if chmod:
        args.extend(["--chmod", chmod])
    return subprocess.run(args, capture_output=True, text=True, timeout=600, cwd=REPO)


def step(title: str) -> None:
    print(f"\n=== {title} ===", flush=True)


def check(rc: subprocess.CompletedProcess[str], label: str) -> None:
    if rc.stdout.strip():
        print(rc.stdout.rstrip())
    if rc.returncode != 0:
        if rc.stderr.strip():
            print(rc.stderr.rstrip(), file=sys.stderr)
        raise SystemExit(f"{label} failed (exit {rc.returncode})")


def main() -> int:
    backup_wsl = "/tmp/kuma-backup.db"
    win_tmp_posix = WIN_TMP_WSL
    install_sh = REPO / "scripts" / "proxmox" / "uptime-kuma-install.sh"
    fix_sh = REPO / "scripts" / "proxmox" / "fix-kuma-monitors-lxc.sh"

    step(f"1. online sqlite backup ({PHONE_IP}), Kuma keeps running")
    rc = phone(
        "sudo sqlite3 /var/lib/uptime-kuma/data/kuma.db "
        "'.backup /tmp/kuma-backup.db' && ls -lh /tmp/kuma-backup.db",
        timeout=120,
    )
    check(rc, "sqlite backup")

    step("2. scp -> Windows TEMP")
    rc = wsl_bash(
        f"scp -o ConnectTimeout=15 -i {WSL_KEY} "
        f"pmos@{PHONE_IP}:/tmp/kuma-backup.db {backup_wsl} && "
        f"cp -f {backup_wsl} {win_tmp_posix} && ls -lh {backup_wsl}",
        timeout=180,
    )
    check(rc, "scp backup")

    step("3. upload to Proxmox host")
    rc = upload(install_sh, "/tmp/uptime-kuma-install.sh", "755")
    check(rc, "upload install script")
    rc = upload(fix_sh, "/tmp/fix-kuma-monitors-lxc.sh", "755")
    check(rc, "upload fix script")
    if not WIN_TMP.is_file():
        raise SystemExit(f"missing {WIN_TMP}")
    rc = upload(WIN_TMP, "/tmp/kuma-backup.db")
    check(rc, "upload db")

    step(f"4. pct push -> LXC {LXC_VMID}")
    for name, perms in (
        ("uptime-kuma-install.sh", " --perms 0755"),
        ("fix-kuma-monitors-lxc.sh", " --perms 0755"),
        ("kuma-backup.db", ""),
    ):
        rc = proxmox(f"pct push {LXC_VMID} /tmp/{name} /tmp/{name}{perms}", timeout=120)
        check(rc, f"push {name}")

    step("5. install Kuma (npm, до ~15 мин)")
    rc = proxmox(
        f"pct exec {LXC_VMID} -- bash -lc 'KUMA_VERSION={KUMA_VERSION} /tmp/uptime-kuma-install.sh'",
        timeout=900,
    )
    check(rc, "install")

    step("6. restore DB + fix monitors")
    rc = proxmox(
        f"pct exec {LXC_VMID} -- bash -lc '"
        "systemctl stop uptime-kuma; "
        "install -d -o uptime-kuma -g uptime-kuma -m 750 /var/lib/uptime-kuma/data; "
        "cp /tmp/kuma-backup.db /var/lib/uptime-kuma/data/kuma.db; "
        "chown uptime-kuma:uptime-kuma /var/lib/uptime-kuma/data/kuma.db'",
        timeout=60,
    )
    check(rc, "restore")
    rc = proxmox(f"pct exec {LXC_VMID} -- bash /tmp/fix-kuma-monitors-lxc.sh", timeout=60)
    check(rc, "fix monitors")

    step("7. disable Kuma on phoneserver (pkill, not rc-service)")
    rc = phone(
        "sudo pkill -f /opt/uptime-kuma/server/server.js 2>/dev/null || true; "
        "sudo rc-update del uptime-kuma default 2>/dev/null || true; "
        "pgrep -af uptime-kuma || echo stopped",
        timeout=30,
    )
    check(rc, "stop phone")

    step("8. verify")
    rc = proxmox(
        f"pct exec {LXC_VMID} -- curl -sS -m 5 -o /dev/null "
        "-w 'kuma:%{{http_code}}\\n' http://127.0.0.1:3001/",
        timeout=30,
    )
    check(rc, "verify")
    print("\ndone — http://192.168.50.35:3001/")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
