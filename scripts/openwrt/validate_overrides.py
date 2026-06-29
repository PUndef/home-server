"""Validate OpenWrt custom overrides against repo manifest and live router state.

Read-only by design: this script must not change UCI, nftables, services, or files
on the router. It verifies the local home-server overrides that sit on top of
podkop/sing-box/zapret dynamic lists.

Usage:
  py -3 scripts/openwrt/validate_overrides.py
  py -3 scripts/openwrt/validate_overrides.py --manifest config/openwrt/overrides.json
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

import paramiko


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "config" / "openwrt" / "overrides.json"
SCRIPTS = ROOT / "scripts" / "openwrt"


class ValidationResult:
    def __init__(self) -> None:
        self.failures: list[str] = []
        self.warnings: list[str] = []

    def fail(self, message: str) -> None:
        self.failures.append(message)

    def warn(self, message: str) -> None:
        self.warnings.append(message)


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


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def get_group(manifest: dict[str, Any], group: str) -> list[str]:
    client_name, _, scope = group.partition(".")
    clients = manifest["clients"]
    if client_name not in clients:
        raise KeyError(f"unknown client group: {group}")
    if scope == "all":
        values: list[str] = []
        for item in clients[client_name].values():
            values.extend(item)
        return values
    if scope not in clients[client_name]:
        raise KeyError(f"unknown client scope: {group}")
    return list(clients[client_name][scope])


def grep_needles(label: str, text: str, needles: list[str], result: ValidationResult) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        result.fail(f"{label}: missing {', '.join(missing)}")
    else:
        print(f"[OK] {label}")


def file_sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def remote_sha256(client: paramiko.SSHClient, remote: str) -> str | None:
    code, out = run(client, f"sha256sum {remote} 2>/dev/null | awk '{{print $1}}'")
    if code != 0 or not out.strip():
        return None
    return out.strip().split()[0]


def policy_name_from_baseline(manifest: dict[str, Any], key: str, primary: str) -> str:
    item = manifest["pbr_baseline"][key]
    if "name" in item:
        return item["name"]
    return item["name_template"].format(primary=primary)


def check_local_files(manifest: dict[str, Any], result: ValidationResult) -> None:
    apply_text = (SCRIPTS / "apply-pundef-pc-routes.sh").read_text(encoding="utf-8")
    zapret_text = (SCRIPTS / "custom.bypass_devices.sh").read_text(encoding="utf-8")
    workvpn_text = (SCRIPTS / "enable-workvpn-client.sh").read_text(encoding="utf-8")

    discord_domains = manifest["pbr_overrides"]["discord"]["domains"]
    destiny_domains = manifest["pbr_overrides"]["destiny_auth"]["domains"]
    destiny_dst = manifest["zapret_bypass"]["destiny_activity"]["dst"]
    forbidden = manifest["zapret_bypass"]["destiny_activity"]["forbidden"]
    baseline = manifest["pbr_baseline"]

    grep_needles("local apply script Discord domains", apply_text, discord_domains, result)
    grep_needles("local apply script Destiny domains", apply_text, destiny_domains, result)
    for key in ("steam", "nexus", "ru_local", "lib_ddg", "warframe"):
        grep_needles(f"local apply script {key} domains", apply_text, baseline[key]["domains"], result)
    grep_needles("local zapret hook Destiny nets", zapret_text, destiny_dst, result)

    sdr = manifest["zapret_bypass"]["destiny_steam_sdr"]
    grep_needles("local zapret hook Steam SDR clients", zapret_text, sdr["src"], result)
    if sdr.get("udp_dport") and sdr["udp_dport"] not in zapret_text:
        result.fail(f"local zapret hook missing Steam SDR dport {sdr['udp_dport']}")
    else:
        print("[OK] local zapret hook Steam SDR dport")

    for key in ("phoneserver_wlan", "pundef_pc_eth_tcp", "xiaomi_13t_pro", "srv_subnet"):
        zb = manifest["zapret_bypass"][key]
        for src in zb.get("src", []):
            if src not in zapret_text:
                result.fail(f"local zapret hook missing generated device src {src} ({key})")
        if all(src in zapret_text for src in zb.get("src", [])):
            print(f"[OK] local zapret hook device block includes {key}")

    destiny_line = re.search(r'^DESTINY_NETS="(?P<nets>[^"]+)"', zapret_text, re.MULTILINE)
    destiny_value = destiny_line.group("nets") if destiny_line else ""
    for forbidden_net in forbidden:
        if forbidden_net in destiny_value:
            result.fail(f"local DESTINY_NETS contains forbidden net {forbidden_net}")
        else:
            print(f"[OK] local DESTINY_NETS excludes {forbidden_net}")

    workvpn = manifest["workvpn"]
    grep_needles("local workvpn destinations", workvpn_text, workvpn["destinations"], result)
    grep_needles(
        "local workvpn guard clients",
        workvpn_text,
        [client["policy"] for client in workvpn["clients"] if client["name"] != "xiaomi-13t-pro"],
        result,
    )


def check_remote_hash(client: paramiko.SSHClient, manifest: dict[str, Any], result: ValidationResult) -> None:
    auto = manifest["automation"]
    pairs = (
        ("apply", SCRIPTS / "apply-pundef-pc-routes.sh", auto["apply_routes"]),
        ("zapret", SCRIPTS / "custom.bypass_devices.sh", auto["zapret_hook"]),
        ("login", SCRIPTS / "destiny-login-mode.sh", auto["destiny_login"]),
        ("normal", SCRIPTS / "destiny-normal-mode.sh", auto["destiny_normal"]),
    )
    for label, local, remote in pairs:
        local_hash = file_sha256(local)
        remote_hash = remote_sha256(client, remote)
        if remote_hash is None:
            result.fail(f"remote {label} script missing: {remote}")
        elif local_hash != remote_hash:
            result.fail(f"remote {label} script hash drift: {remote}")
        else:
            print(f"[OK] remote {label} script matches repo")


def check_destiny_modes(client: paramiko.SSHClient, manifest: dict[str, Any], result: ValidationResult) -> None:
    flag = manifest["destiny_modes"]["flag"]
    _, primary = run(client, "uci -q get podkop.main.interface || echo awg2")
    primary = primary.strip() or "awg2"

    code, pbr = run(client, "uci show pbr 2>/dev/null")
    pbr_text = pbr if code == 0 else ""

    _, flag_state = run(client, f"test -f {flag} && echo on || echo off")
    login_active = flag_state.strip() == "on"

    steam_normal = manifest["pbr_baseline"]["steam"]["name"]
    login_steam = manifest["destiny_modes"]["login"]["steam_policy"]["name_template"].format(primary=primary)
    static_ips = manifest["destiny_modes"]["login"].get("static_ips", [])

    if login_active:
        if login_steam not in pbr_text:
            result.fail(f"stuck login mode: flag set but missing policy {login_steam}")
        elif steam_normal in pbr_text:
            result.fail("stuck login mode: flag set but normal steam policy still present")
        else:
            print("[OK] router destiny login mode active with login steam policy")
        for ip in static_ips:
            if f"{ip}/32" not in pbr_text:
                result.warn(f"login mode: Steam auth static IP {ip}/32 not in pbr dest_addr")
            else:
                print(f"[OK] login mode routes Steam auth IP {ip}/32")
    else:
        if login_steam in pbr_text and "(destiny login)" in login_steam:
            result.fail(f"incomplete normal restore: login steam policy still present ({login_steam})")
        code, _ = run(client, f"uci show pbr 2>/dev/null | grep -q \"name='{steam_normal}'\"")
        if code != 0:
            result.fail(f"normal mode missing baseline policy: {steam_normal}")
        else:
            print(f"[OK] router normal mode has {steam_normal}")
            result.warn(
                "normal mode + cold Destiny login risk: Steam auth may route via WAN; "
                "use apply_overrides.py --mode login before cold start"
            )


def check_baseline_policies(client: paramiko.SSHClient, manifest: dict[str, Any], result: ValidationResult) -> None:
    _, primary = run(client, "uci -q get podkop.main.interface || echo awg2")
    primary = primary.strip() or "awg2"
    code, pbr = run(client, "uci show pbr 2>/dev/null")
    pbr_text = pbr if code == 0 else ""

    for key in ("steam", "nexus", "ru_local", "lib_ddg", "warframe"):
        policy_name = policy_name_from_baseline(manifest, key, primary)
        if policy_name in pbr_text:
            print(f"[OK] router baseline policy present: {policy_name}")
        else:
            result.fail(f"router baseline policy missing: {policy_name}")

    srv_name = manifest["pbr_baseline"]["srv_default"]["name_template"].format(primary=primary)
    if srv_name in pbr_text:
        print(f"[OK] router baseline policy present: {srv_name}")
    else:
        result.fail(f"router baseline policy missing: {srv_name}")


def check_router(client: paramiko.SSHClient, manifest: dict[str, Any], result: ValidationResult) -> None:
    auto = manifest["automation"]
    remote_apply = auto["apply_routes"]
    remote_hook = auto["zapret_hook"]

    _, primary = run(client, "uci -q get podkop.main.interface || echo awg2")
    primary = primary.strip() or "awg2"

    code, pbr = run(client, "uci show pbr 2>/dev/null")
    if code != 0:
        result.fail("router pbr config unreadable")
        pbr = ""

    code, prerouting = run(client, "nft list chain inet fw4 pbr_prerouting 2>/dev/null")
    if code != 0:
        result.fail("router pbr_prerouting chain unreadable")
        prerouting = ""

    code, discord_set = run(client, "nft list set inet fw4 pbr_awg2_4_dst_ip_discord_pundef 2>/dev/null")
    if code != 0 or "162.159." not in discord_set:
        result.fail("router Discord pbr nftset missing or not seeded")
    else:
        print("[OK] router Discord pbr nftset seeded")

    discord_name = manifest["pbr_overrides"]["discord"]["name_template"].format(primary=primary)
    destiny_name = manifest["pbr_overrides"]["destiny_auth"]["name_template"].format(primary=primary)
    for policy_name in (discord_name, destiny_name):
        if policy_name in pbr and policy_name in prerouting:
            print(f"[OK] router pbr policy active: {policy_name}")
        else:
            result.fail(f"router pbr policy missing/inactive: {policy_name}")

    check_baseline_policies(client, manifest, result)
    check_destiny_modes(client, manifest, result)
    check_remote_hash(client, manifest, result)

    workvpn = manifest["workvpn"]
    code, workvpn_status = run(client, "ifstatus workvpn 2>/dev/null")
    if code == 0 and '"up": true' in workvpn_status:
        print("[OK] router workvpn interface is up")
    else:
        result.fail("router workvpn interface is down/unreadable")

    code, workvpn_route = run(client, f"ip route show table {workvpn['route_table']} 2>/dev/null")
    if code == 0 and "default" in workvpn_route and "vpn-workvpn" in workvpn_route:
        print(f"[OK] router {workvpn['route_table']} has default via vpn-workvpn")
    else:
        result.fail(f"router {workvpn['route_table']} default route missing: {workvpn_route or 'empty'}")

    code, dhcp = run(client, "uci show dhcp 2>/dev/null")
    if code == 0:
        dns = workvpn["dns"]
        dns_needles = [f"/{dns['domain']}/{dns['upstream']}"]
        dns_needles.extend(f"/{host}/{ip}" for host, ip in dns["static_hosts"].items())
        missing_dns = [needle for needle in dns_needles if needle not in dhcp]
        if missing_dns:
            for needle in missing_dns:
                result.warn(f"router workvpn DNS missing {needle} (known drift — ACT via enable-workvpn-client.sh)")
        else:
            print("[OK] router workvpn DNS overrides present")
    else:
        result.fail("router dhcp config unreadable for workvpn DNS checks")

    for workvpn_client in workvpn["clients"]:
        policy = workvpn_client["policy"]
        src = workvpn_client["src"]
        if policy in pbr and src in pbr:
            print(f"[OK] router workvpn policy: {policy} ({src})")
        else:
            result.fail(f"router workvpn policy missing/incomplete: {policy} ({src})")

    missing_destinations = [d for d in workvpn["destinations"] if d not in pbr]
    if missing_destinations:
        for destination in missing_destinations:
            result.fail(f"router workvpn destination missing from pbr: {destination}")
    else:
        print("[OK] router workvpn destinations present in pbr")

    code, zapret_post = run(client, "nft list chain inet zapret postnat 2>/dev/null")
    code_pre, zapret_pre = run(client, "nft list chain inet zapret prenat 2>/dev/null")
    if code != 0 or code_pre != 0:
        result.fail("router zapret chains unreadable")
        zapret = ""
    else:
        zapret = f"{zapret_post}\n{zapret_pre}"

    destiny_dst = manifest["zapret_bypass"]["destiny_activity"]["dst"]
    missing_zapret = []
    for dst in destiny_dst:
        short = dst.removesuffix("/32")
        if short not in zapret and dst not in zapret:
            missing_zapret.append(dst)
    if missing_zapret:
        for dst in missing_zapret:
            result.fail(f"router zapret Destiny bypass missing {dst}")
    else:
        print("[OK] router zapret Destiny bypass nets present")

    steam_sdr = manifest["zapret_bypass"].get("destiny_steam_sdr", {})
    for src in steam_sdr.get("src", []):
        suffix = src.rsplit(".", 1)[-1]
        if f"zapret-ct-bypass-{suffix}-steam-sdr" in zapret:
            print(f"[OK] router zapret Steam SDR bypass for .{suffix}")
        else:
            result.fail(f"router zapret Steam SDR bypass missing for {src}")

    for forbidden_net in manifest["zapret_bypass"]["destiny_activity"]["forbidden"]:
        short = forbidden_net.removesuffix("/24")
        if re.search(rf"ip daddr \{{[^}}]*{re.escape(short)}|ip daddr {re.escape(forbidden_net)}", zapret):
            result.fail(f"router zapret contains forbidden net {forbidden_net}")
        else:
            print(f"[OK] router zapret excludes {forbidden_net}")

    for key in ("phoneserver_wlan", "pundef_pc_eth_tcp", "xiaomi_13t_pro", "srv_subnet"):
        zb = manifest["zapret_bypass"][key]
        for src in zb.get("src", []):
            suffix = src.rsplit(".", 1)[-1] if "/" not in src else "srv"
            if key == "srv_subnet":
                needle = "zapret-ct-bypass-srv"
            elif key == "pundef_pc_eth_tcp":
                needle = f"zapret-ct-bypass-{suffix}-tcp"
            else:
                needle = f"zapret-ct-bypass-{suffix}"
            if needle in zapret:
                print(f"[OK] router zapret device bypass present: {needle}")
            else:
                result.fail(f"router zapret device bypass missing: {needle} ({key})")

    code, remote_apply = run(
        client,
        f"grep -E 'DISCORD_DOMAINS|pundef-pc discord|gateway.discord.gg' {remote_apply} 2>/dev/null",
    )
    if code == 0 and "gateway.discord.gg" in remote_apply:
        print("[OK] router apply script includes Discord override")
    else:
        result.fail("router apply script missing Discord override")

    code, remote_hook = run(client, f"grep -E '^DESTINY_NETS=' {remote_hook} 2>/dev/null")
    if code == 0 and "57.129.90.115" in remote_hook and "104.29.154.0/24" not in remote_hook:
        print("[OK] router zapret hook matches Destiny/Discord invariant")
    else:
        result.fail("router zapret hook does not match Destiny/Discord invariant")

    code, cron = run(client, "cat /etc/crontabs/root 2>/dev/null")
    if code == 0:
        missing_cron = [e for e in manifest["automation"]["cron_contains"] if e not in cron]
        if missing_cron:
            for cron_entry in missing_cron:
                result.fail(f"router cron missing {cron_entry}")
        else:
            print("[OK] router cron override watchdogs present")
    else:
        result.fail("router cron unreadable")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    args = parser.parse_args()

    manifest = load_manifest(args.manifest)
    result = ValidationResult()

    check_local_files(manifest, result)
    client = connect()
    try:
        check_router(client, manifest, result)
    finally:
        client.close()

    print()
    if result.warnings:
        print(f"WARNINGS ({len(result.warnings)}):")
        for warning in result.warnings:
            print(f"  - {warning}")
        print()

    if result.failures:
        print(f"FAILED ({len(result.failures)}):")
        for failure in result.failures:
            print(f"  - {failure}")
        return 1

    if result.warnings:
        print("All OpenWrt override checks passed (with warnings).")
    else:
        print("All OpenWrt override checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
