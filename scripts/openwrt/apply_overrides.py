"""Apply OpenWrt overrides from config/openwrt/overrides.json.

Single entry point: validate → generate check → upload → apply → verify.

Usage:
  py -3 scripts/openwrt/apply_overrides.py --check-only
  py -3 scripts/openwrt/apply_overrides.py --mode normal
  py -3 scripts/openwrt/apply_overrides.py --mode login
  py -3 scripts/openwrt/apply_overrides.py --mode login --full
  py -3 scripts/openwrt/apply_overrides.py --mode status
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

import paramiko

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = Path(__file__).resolve().parent
MANIFEST = ROOT / "config" / "openwrt" / "overrides.json"
GENERATE = SCRIPTS / "generate_overrides.py"
VALIDATE = SCRIPTS / "validate_overrides.py"
CHECK = SCRIPTS / "check_gaming_pc_routes.py"

APPLY_SH = SCRIPTS / "apply-pundef-pc-routes.sh"
ZAPRET_SH = SCRIPTS / "custom.bypass_devices.sh"
LOGIN_SH = SCRIPTS / "destiny-login-mode.sh"
NORMAL_SH = SCRIPTS / "destiny-normal-mode.sh"
RESERVE_SH = SCRIPTS / "reserve-pundef-pc-dhcp.sh"
HOTPLUG_LOCAL = SCRIPTS / "99-vpn-stack"
WATCHDOG_SH = SCRIPTS / "pundef-pc-routes-watchdog.sh"
REMOTE_WATCHDOG = "/opt/pundef-pc-routes-watchdog.sh"


def load_manifest(path: Path = MANIFEST) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


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


def run_remote(
    client: paramiko.SSHClient,
    command: str,
    stdin_data: str | None = None,
    timeout: int = 180,
) -> tuple[int, str]:
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


def file_sha256(path: Path) -> str:
    raw = path.read_bytes().replace(b"\r\n", b"\n").replace(b"\r", b"\n")
    return hashlib.sha256(raw).hexdigest()


def remote_sha256(client: paramiko.SSHClient, remote: str) -> str | None:
    code, out = run_remote(client, f"sha256sum {remote} 2>/dev/null | awk '{{print $1}}'")
    if code != 0 or not out.strip():
        return None
    return out.strip().split()[0]


def run_local_script(script: Path, *args: str) -> int:
    proc = subprocess.run([sys.executable, str(script), *args], cwd=str(ROOT))
    return proc.returncode


def destiny_flag(manifest: dict[str, Any]) -> str:
    return manifest["destiny_modes"]["flag"]


def remote_paths(manifest: dict[str, Any]) -> dict[str, str]:
    auto = manifest["automation"]
    return {
        "apply": auto["apply_routes"],
        "zapret": auto["zapret_hook"],
        "login": auto["destiny_login"],
        "normal": auto["destiny_normal"],
        "hotplug": auto["hotplug"],
    }


def upload_scripts(client: paramiko.SSHClient, manifest: dict[str, Any], skip_zapret: bool = False) -> None:
    paths = remote_paths(manifest)
    upload_file(client, APPLY_SH, paths["apply"])
    upload_file(client, LOGIN_SH, paths["login"])
    upload_file(client, NORMAL_SH, paths["normal"])
    if not skip_zapret:
        upload_file(client, ZAPRET_SH, paths["zapret"])
    if HOTPLUG_LOCAL.exists():
        upload_file(client, HOTPLUG_LOCAL, paths["hotplug"])


def check_repo_remote_hash(client: paramiko.SSHClient, manifest: dict[str, Any], failures: list[str]) -> None:
    paths = remote_paths(manifest)
    for label, local, remote in (
        ("apply", APPLY_SH, paths["apply"]),
        ("zapret", ZAPRET_SH, paths["zapret"]),
        ("login", LOGIN_SH, paths["login"]),
        ("normal", NORMAL_SH, paths["normal"]),
    ):
        local_hash = file_sha256(local)
        remote_hash = remote_sha256(client, remote)
        if remote_hash is None:
            failures.append(f"remote {label} script missing: {remote}")
        elif local_hash != remote_hash:
            failures.append(f"remote {label} script drift: {remote}")


def live_session_active(client: paramiko.SSHClient, wlan_ip: str = "192.168.1.208") -> bool:
    code, out = run_remote(
        client,
        f"ss -Hun state established '( dport = :19315 or dport = :3074 or sport = :3074 )' "
        f"2>/dev/null | grep -c '{wlan_ip}' || true",
        timeout=15,
    )
    if code != 0:
        return False
    try:
        return int(out.strip() or "0") > 0
    except ValueError:
        return False


def apply_zapret_hook(client: paramiko.SSHClient, manifest: dict[str, Any]) -> None:
    hook = remote_paths(manifest)["zapret"]
    code, output = run_remote(client, f"sh {hook}")
    print(output)
    if code != 0:
        raise RuntimeError(f"zapret hook failed: {hook}")


def reserve_dhcp(client: paramiko.SSHClient) -> None:
    if not RESERVE_SH.exists():
        return
    print("Reserving pundef-pc DHCP (lan + srv Mercusys)...")
    code, output = run_remote(client, "sh -s", stdin_data=RESERVE_SH.read_text(encoding="utf-8"))
    print(output)
    if code != 0:
        raise RuntimeError("reserve-pundef-pc-dhcp failed")


def install_cron(client: paramiko.SSHClient) -> None:
    upload_file(client, WATCHDOG_SH, REMOTE_WATCHDOG)
    cron_line = f"*/15 * * * * {REMOTE_WATCHDOG}"
    _, existing = run_remote(client, "cat /etc/crontabs/root 2>/dev/null || true")
    if "pundef-pc-routes-watchdog" in existing:
        print("cron watchdog already installed")
        return
    run_remote(client, f"(echo '{cron_line}') >> /etc/crontabs/root && /etc/init.d/cron restart")
    print("cron watchdog installed (every 15 min)")


def apply_normal(client: paramiko.SSHClient, manifest: dict[str, Any]) -> None:
    flag = destiny_flag(manifest)
    paths = remote_paths(manifest)
    run_remote(client, f"rm -f {flag}")
    reserve_dhcp(client)
    code, output = run_remote(client, f"sh {paths['apply']}")
    print(output)
    if code != 0:
        raise RuntimeError("apply-pundef-pc-routes failed")


def apply_login(
    client: paramiko.SSHClient,
    manifest: dict[str, Any],
    full: bool = False,
    tunnel: str | None = None,
) -> None:
    paths = remote_paths(manifest)
    login_args = " --full" if full else ""
    env = f"PRIMARY={tunnel} " if tunnel else ""
    code, output = run_remote(client, f"{env}sh {paths['login']}{login_args}")
    print(output)
    if code != 0:
        raise RuntimeError("destiny login mode failed")


def verify_after_apply(client: paramiko.SSHClient, manifest: dict[str, Any], mode: str) -> list[str]:
    failures: list[str] = []
    flag = destiny_flag(manifest)
    paths = remote_paths(manifest)
    _, primary = run_remote(client, "uci -q get podkop.main.interface || echo awg2")
    primary = primary.strip() or "awg2"

    _, flag_state = run_remote(client, f"test -f {flag} && echo on || echo off")
    if mode == "normal":
        if flag_state.strip() == "on":
            failures.append("login flag still set after normal apply")
        code, _ = run_remote(client, "uci show pbr 2>/dev/null | grep -q \"name='pundef-pc steam via wan'\"")
        if code != 0:
            failures.append("missing pundef-pc steam via wan after normal apply")
    elif mode == "login":
        if flag_state.strip() != "on":
            failures.append("login flag not set after login apply")
        steam_name = manifest["destiny_modes"]["login"]["steam_policy"]["name_template"].format(primary=primary)
        code, _ = run_remote(client, f"uci show pbr 2>/dev/null | grep -q \"name='{steam_name}'\"")
        if code != 0:
            failures.append(f"missing login steam policy: {steam_name}")

    code, output = run_remote(client, f"sh {paths['apply']} --check-only")
    print(output)
    if code != 0 and mode == "normal":
        failures.append("apply --check-only failed after normal apply")
    return failures


def print_login_instructions() -> None:
    print("\n=== LOGIN MODE ===")
    print("1. Quit Steam fully (tray too)")
    print("2. Start Steam again")
    print("3. Launch Destiny 2")
    print("4. Play until you are IN THE WORLD (tower / ship / patrol) — NOT character select")
    print("5. Only then:")
    print("   py -3 scripts/openwrt/apply_overrides.py --mode normal")


def print_normal_instructions() -> None:
    print("\n=== NORMAL MODE ===")
    print("Steam -> WAN again (fast downloads).")
    print("If Destiny is open, expect disconnect — run only when idle or fully in-world.")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apply OpenWrt overrides from manifest")
    parser.add_argument(
        "--mode",
        choices=("normal", "login", "status", "check-only"),
        default="normal",
        help="normal=baseline routes, login=Destiny auth tunnel, status=read state, check-only=validate only",
    )
    parser.add_argument("--full", action="store_true", help="Login mode: route all lan egress via primary tunnel")
    parser.add_argument("--tunnel", choices=("awg1", "awg2"), help="Override primary tunnel for login mode")
    parser.add_argument("--check-only", action="store_true", help="Alias for --mode check-only")
    parser.add_argument("--skip-validate", action="store_true", help="Skip read-only validate_overrides pre-check")
    parser.add_argument("--skip-check", action="store_true", help="Skip check_gaming_pc_routes after apply")
    parser.add_argument("--skip-upload", action="store_true", help="Do not upload scripts (apply remote /opt only)")
    parser.add_argument(
        "--force-live-session",
        action="store_true",
        help="Allow pbr restart while Discord/Destiny UDP sessions may be active",
    )
    parser.add_argument(
        "--install-cron",
        action="store_true",
        help="Install pundef-pc-routes watchdog cron on router (can combine with --mode normal)",
    )
    parser.add_argument("--manifest", type=Path, default=MANIFEST)
    args = parser.parse_args()

    if args.check_only:
        args.mode = "check-only"

    manifest = load_manifest(args.manifest)

    print("=== generate --check ===")
    if run_local_script(GENERATE, "--check", "--manifest", str(args.manifest)) != 0:
        return 1

    if args.mode == "check-only":
        print("\n=== validate_overrides ===")
        return run_local_script(VALIDATE, "--manifest", str(args.manifest))

    if not args.skip_validate:
        print("\n=== validate_overrides (pre) ===")
        pre = run_local_script(VALIDATE, "--manifest", str(args.manifest))
        if pre != 0:
            print("Pre-validate failed; continuing apply because explicit mode was requested.")

    client = connect()
    try:
        if args.mode == "status":
            flag = destiny_flag(manifest)
            _, flag_kind = run_remote(client, f"cat {flag} 2>/dev/null || echo normal")
            _, primary = run_remote(client, "uci -q get podkop.main.interface || echo awg2")
            _, steam = run_remote(
                client,
                "for i in 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do "
                "n=$(uci -q get pbr.@policy[$i].name 2>/dev/null || true); "
                "case \"$n\" in 'pundef-pc steam via '*) echo \"$n -> $(uci -q get pbr.@policy[$i].interface)\"; exit 0;; esac; "
                "done; echo missing",
            )
            print(f"mode={flag_kind.strip()} primary={primary.strip()} steam_policy={steam.strip()}")
            return 0

        if not args.force_live_session and live_session_active(client):
            print(
                "Refusing apply: active Discord/Destiny UDP session on .208 detected. "
                "Retry with --force-live-session if intentional."
            )
            return 1

        if not args.skip_upload:
            print("\n=== upload scripts ===")
            upload_scripts(client, manifest)

        if args.install_cron:
            print("\n=== install cron watchdog ===")
            install_cron(client)

        if args.mode == "normal":
            print("\n=== apply normal ===")
            apply_normal(client, manifest)
        elif args.mode == "login":
            print("\n=== apply login ===")
            apply_login(client, manifest, full=args.full, tunnel=args.tunnel)

        if args.mode in ("normal", "login") and not args.skip_upload:
            print("\n=== apply zapret hook (no restart) ===")
            apply_zapret_hook(client, manifest)

        print("Waiting 20s for pbr/dnsmasq settle...")
        time.sleep(20)

        failures = verify_after_apply(client, manifest, args.mode)
        if failures:
            print("VERIFY FAILED:")
            for failure in failures:
                print(f"  - {failure}")
            return 1

        if not args.skip_validate:
            print("\n=== validate_overrides (post) ===")
            run_local_script(VALIDATE, "--manifest", str(args.manifest))

        if not args.skip_check and CHECK.exists() and args.mode == "normal":
            print("\n=== check_gaming_pc_routes ===")
            if run_local_script(CHECK) != 0:
                return 1

        if args.mode == "login":
            print_login_instructions()
        elif args.mode == "normal":
            print_normal_instructions()

        print("\n=== OK ===")
        return 0
    finally:
        client.close()


if __name__ == "__main__":
    raise SystemExit(main())
