"""Collect OpenWrt pundef-pc routing status as JSON (read-only).

Usage:
  py -3 scripts/openwrt/routing_status.py
  py -3 scripts/openwrt/routing_status.py --out /srv/static-sites/network-routing/status.json
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import paramiko

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "config" / "openwrt" / "overrides.json"

# BEGIN GENERATED: openwrt-overrides check expectations
# Generated from config/openwrt/overrides.json. Edit the manifest, not this block.
CHECK_REQUIRED_POLICIES_NORMAL = (
    "pundef-pc steam auth via {primary}",
    "pundef-pc steam cdn via wan",
    "pundef-pc nexus via wan",
    "pundef-pc ru-local via wan",
    "pundef-pc discord via {primary}",
    "pundef-pc destiny via {primary}",
    "Warframe via {primary}",
)
CHECK_DNS_RESOLVE_HOSTS = (
    "discord.com",
    "bungie.net",
    "store.steampowered.com",
    "2gis.ru",
)
CHECK_DESTINY_NO_A = (
    "steamserver.net",
    "deadorbit.net",
    "gravityshavings.net",
)
CHECK_STEAM_ROUTE_TEST_IP = "23.61.239.50"
CHECK_ZAPRET_DESTINY_NETS = (
    "57.129.90.115/32",
    "172.97.56.0/24",
    "155.133.0.0/16",
    "162.254.0.0/16",
    "205.196.0.0/16",
    "205.209.0.0/16",
)
CHECK_STEAM_AUTH_ROUTE_TEST_IP = "199.165.136.100"
# END GENERATED: openwrt-overrides check expectations


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


def run(client: paramiko.SSHClient, cmd: str) -> tuple[int, str]:
    _stdin, stdout, stderr = client.exec_command(cmd, timeout=60)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return stdout.channel.recv_exit_status(), (out + ("\n" + err if err else "")).strip()


def check_item(name: str, ok: bool, detail: str, level: str = "ok") -> dict[str, Any]:
    if ok:
        status = "ok"
    else:
        status = level
    return {"name": name, "status": status, "detail": detail}


def parse_route_interface(route: str, primary: str) -> str:
    if f"dev {primary}" in route:
        return primary
    if " dev wan " in route:
        return "wan"
    match = re.search(r"dev (\S+)", route)
    return match.group(1) if match else "unknown"


def collect(client: paramiko.SSHClient, manifest: dict[str, Any]) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    _, primary = run(client, "uci -q get podkop.main.interface || echo awg2")
    primary = primary.strip() or "awg2"

    flag_path = manifest["destiny_modes"]["flag"]
    _, flag_state = run(client, f"test -f {flag_path} && echo on || echo off")
    login_flag = flag_state.strip() == "on"
    if login_flag:
        checks.append(check_item("legacy login flag", False, f"{flag_path} still present", "fail"))
    else:
        checks.append(check_item("legacy login flag", True, "not set (baseline mode)"))

    code, pbr = run(client, "uci show pbr 2>/dev/null")
    pbr_text = pbr if code == 0 else ""
    policies: list[dict[str, str]] = []
    if code == 0:
        _, policy_lines = run(
            client,
            "i=0; while uci -q get pbr.@policy[$i] >/dev/null 2>&1; do "
            "n=$(uci -q get pbr.@policy[$i].name 2>/dev/null || true); "
            "iface=$(uci -q get pbr.@policy[$i].interface 2>/dev/null || true); "
            "case \"$n\" in 'pundef-pc '*|'Warframe '*) echo \"$n|$iface\";; esac; "
            "i=$((i+1)); done",
        )
        for line in policy_lines.splitlines():
            if "|" not in line:
                continue
            name, iface = line.split("|", 1)
            policies.append({"name": name.strip(), "interface": iface.strip() or "?"})

    for policy_tpl in CHECK_REQUIRED_POLICIES_NORMAL:
        policy_name = policy_tpl.format(primary=primary)
        present = policy_name in pbr_text
        checks.append(
            check_item(
                f"policy {policy_name}",
                present,
                "present" if present else "missing",
                "fail",
            )
        )

    if "pundef-pc steam via wan" in pbr_text:
        checks.append(check_item("legacy steam via wan", False, "still present", "fail"))
    if "(destiny login)" in pbr_text:
        checks.append(check_item("legacy destiny login policy", False, "still present", "fail"))

    auth_ip = CHECK_STEAM_AUTH_ROUTE_TEST_IP
    _, auth_route = run(
        client,
        f"ip route get {auth_ip} from 192.168.1.208 iif br-lan mark 0x40000 2>/dev/null | head -1",
    )
    auth_iface = parse_route_interface(auth_route, primary)
    auth_ok = auth_iface == primary
    checks.append(
        check_item(
            "Destiny login path (steam auth IP)",
            auth_ok,
            f"{auth_ip} from .208 mark 0x40000 -> {auth_iface} ({auth_route or 'empty'})",
            "fail",
        )
    )

    cdn_ip = CHECK_STEAM_ROUTE_TEST_IP
    _, cdn_route = run(
        client,
        f"ip route get {cdn_ip} from 192.168.1.208 iif br-lan mark 0x10000 2>/dev/null | head -1",
    )
    cdn_iface = parse_route_interface(cdn_route, primary)
    cdn_ok = cdn_iface == "wan"
    checks.append(
        check_item(
            "Steam CDN path",
            cdn_ok,
            f"{cdn_ip} from .208 -> {cdn_iface} ({cdn_route or 'empty'})",
            "fail",
        )
    )

    code, nft = run(client, "nft list chain inet fw4 pbr_prerouting 2>/dev/null")
    catch_ok = not (code == 0 and "0.0.0.0/0" in nft and "games via" in nft)
    checks.append(
        check_item(
            "no lan catch-all",
            catch_ok,
            "ok" if catch_ok else "catch-all still in nft",
            "fail",
        )
    )

    code_post, zapret_post = run(client, "nft list chain inet zapret postnat 2>/dev/null")
    code_pre, zapret_pre = run(client, "nft list chain inet zapret prenat 2>/dev/null")
    zapret_all = f"{zapret_post}\n{zapret_pre}"
    if code_post == 0 and code_pre == 0:
        discord_voice_bad = bool(
            re.search(r"ip daddr \{[^}]*104\.29\.154|ip daddr 104\.29\.154/", zapret_all)
        )
        checks.append(
            check_item(
                "discord voice not in zapret bypass",
                not discord_voice_bad,
                "104.29.154.0/24 absent" if not discord_voice_bad else "104.29.154 in bypass",
                "fail",
            )
        )
        destiny_ok = all(
            n.removesuffix("/32") in zapret_all or n in zapret_all for n in CHECK_ZAPRET_DESTINY_NETS
        )
        checks.append(
            check_item(
                "destiny zapret bypass nets",
                destiny_ok,
                "present" if destiny_ok else "missing ranges",
                "fail",
            )
        )
    else:
        checks.append(check_item("zapret chains", False, "unreadable", "fail"))

    _, log_tail = run(client, "logread -e pundef-pc 2>/dev/null | tail -n 20")
    log_lines = [line for line in log_tail.splitlines() if line.strip()]

    fail_count = sum(1 for c in checks if c["status"] == "fail")
    warn_count = sum(1 for c in checks if c["status"] == "warn")
    ok_count = sum(1 for c in checks if c["status"] == "ok")
    overall = "fail" if fail_count else ("warn" if warn_count else "ok")

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "mode": "baseline",
        "primary": primary,
        "login_flag": login_flag,
        "policies": policies,
        "routes": {
            "steam_auth": {
                "ip": auth_ip,
                "from": "192.168.1.208",
                "mark": "0x40000",
                "interface": auth_iface,
                "raw": auth_route,
                "status": "ok" if auth_ok else "fail",
            },
            "steam_cdn": {
                "ip": cdn_ip,
                "from": "192.168.1.208",
                "mark": "0x10000",
                "interface": cdn_iface,
                "raw": cdn_route,
                "status": "ok" if cdn_ok else "fail",
            },
        },
        "checks": checks,
        "log_tail": log_lines,
        "summary": {
            "ok": ok_count,
            "warn": warn_count,
            "fail": fail_count,
            "overall": overall,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--out", type=Path, help="Write JSON snapshot to file")
    args = parser.parse_args()

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    client = connect()
    try:
        snapshot = collect(client, manifest)
    finally:
        client.close()

    payload = json.dumps(snapshot, ensure_ascii=False, indent=2)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(payload + "\n", encoding="utf-8")
        print(f"Wrote {args.out}")
    else:
        print(json.dumps(snapshot, ensure_ascii=True, indent=2))
    return 0 if snapshot["summary"]["overall"] != "fail" else 1


if __name__ == "__main__":
    raise SystemExit(main())



