"""Steam routing check for a LAN client: current path + optional speed compare.

Resolves common Steam hostnames via router DNS, evaluates pbr path for the
client (default pundef-pc 192.168.1.133), optionally benchmarks download
speed via wan / awg1 / awg2 on the router.

Usage:
  py -3 scripts/openwrt/check_steam_route.py
  py -3 scripts/openwrt/check_steam_route.py --benchmark
  py -3 scripts/openwrt/check_steam_route.py --live
  py -3 scripts/openwrt/check_steam_route.py --client-ip 192.168.1.133

Environment: OPENWRT_HOST, OPENWRT_USER, OPENWRT_KEY
"""

from __future__ import annotations

import argparse
import ipaddress
import os
import re
import shlex
import sys
from dataclasses import dataclass

import paramiko

FAKE_IP_NET = ipaddress.ip_network("198.18.0.0/15")
PODKOP_MARK = 0x100000

STEAM_DOMAINS = (
    "steampowered.com",
    "store.steampowered.com",
    "api.steampowered.com",
    "steamcommunity.com",
    "steamcdn-a.akamaihd.net",
    "cdn.akamai.steamstatic.com",
    "client-update.akamai.steamstatic.com",
    "media.steampowered.com",
    "steamcontent.com",
)

# Small public Steam CDN asset (~50 KB).
BENCHMARK_URL = "https://steamcdn-a.akamaihd.net/steam/apps/730/header.jpg"

MARK_TO_IFACE = {
    0x010000: "wan",
    0x020000: "awg1",
    0x030000: "workvpn",
    0x040000: "awg2",
}

IFACE_EGRESS = {
    "wan": "ISP (WAN)",
    "awg1": "Fin VPS (awg1)",
    "awg2": "Neth NL (awg2)",
    "workvpn": "corp VPN (workvpn)",
    "podkop": "podkop -> sing-box -> primary tunnel",
}


@dataclass(frozen=True)
class PbrRule:
    src: str | None
    dst_kind: str  # "any", "set", "cidrs"
    dst_value: str
    mark: int
    comment: str


@dataclass(frozen=True)
class PathResult:
    policy: str
    iface: str
    detail: str


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


def run(client: paramiko.SSHClient, command: str, timeout: int = 120) -> str:
    _stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return (out + ("\n" + err if err else "")).strip()


def parse_resolved_ipv4(nslookup_output: str) -> list[str]:
    addresses: list[str] = []
    for line in nslookup_output.splitlines():
        match = re.search(r"Address(?:\s+\d+)?:\s*([0-9]+(?:\.[0-9]+){3})(?:\s|$)", line)
        if not match:
            continue
        ip = match.group(1)
        if ip == "192.168.1.1" or ip in addresses:
            continue
        addresses.append(ip)
    return addresses


def resolve_domain(client: paramiko.SSHClient, domain: str) -> list[str]:
    output = run(client, f"nslookup {shlex.quote(domain)} 192.168.1.1")
    return parse_resolved_ipv4(output)


def parse_pbr_rules(nft_chain: str) -> list[PbrRule]:
    rules: list[PbrRule] = []
    for line in nft_chain.splitlines():
        line = line.strip()
        if " goto pbr_mark_" not in line:
            continue

        src_match = re.search(r"ip saddr (\S+)", line)
        src = src_match.group(1) if src_match else None

        if "ip daddr 0.0.0.0/0" in line:
            dst_kind, dst_value = "any", "0.0.0.0/0"
        elif "ip daddr @" in line:
            dst_match = re.search(r"ip daddr (@\S+)", line)
            dst_kind = "set"
            dst_value = dst_match.group(1) if dst_match else ""
        elif "ip daddr {" in line:
            dst_match = re.search(r"ip daddr \{ ([^}]+) \}", line)
            dst_kind = "cidrs"
            dst_value = dst_match.group(1) if dst_match else ""
        else:
            continue

        mark_match = re.search(r"pbr_mark_0x([0-9a-fA-F]+)", line)
        comment_match = re.search(r'comment "([^"]+)"', line)
        if not mark_match:
            continue
        mark = int(mark_match.group(1), 16)
        comment = comment_match.group(1) if comment_match else "unknown"
        rules.append(PbrRule(src=src, dst_kind=dst_kind, dst_value=dst_value, mark=mark, comment=comment))
    return rules


def ip_in_cidrs(ip_text: str, cidrs_text: str) -> bool:
    ip = ipaddress.ip_address(ip_text)
    for part in cidrs_text.split(","):
        part = part.strip()
        if not part:
            continue
        try:
            if ip in ipaddress.ip_network(part, strict=False):
                return True
        except ValueError:
            continue
    return False


def ip_in_nft_set(client: paramiko.SSHClient, set_name: str, ip_text: str) -> bool:
    # set_name like @pbr_awg2_4_dst_ip_cfg016ff5
    table_set = set_name.lstrip("@")
    cmd = (
        f"nft get element inet fw4 {shlex.quote(table_set)} "
        f"{{ {shlex.quote(ip_text)} }} 2>/dev/null && echo YES || echo NO"
    )
    return run(client, cmd).strip().endswith("YES")


def ip_in_podkop_subnets(client: paramiko.SSHClient, ip_text: str) -> bool:
    output = run(client, "nft list set inet PodkopTable podkop_subnets 2>/dev/null || true")
    patterns = re.findall(
        r"\b[0-9]+(?:\.[0-9]+){3}(?:/[0-9]+|-[0-9]+(?:\.[0-9]+){3})?\b",
        output,
    )
    ip = ipaddress.ip_address(ip_text)
    for pattern in patterns:
        try:
            if "-" in pattern:
                start, end = pattern.split("-", maxsplit=1)
                if ipaddress.ip_address(start) <= ip <= ipaddress.ip_address(end):
                    return True
            elif "/" in pattern:
                if ip in ipaddress.ip_network(pattern, strict=False):
                    return True
            elif ip == ipaddress.ip_address(pattern):
                return True
        except ValueError:
            continue
    return False


def evaluate_path(
    client: paramiko.SSHClient,
    rules: list[PbrRule],
    client_ip: str,
    dst_ip: str,
) -> PathResult:
    ip = ipaddress.ip_address(dst_ip)
    if ip in FAKE_IP_NET:
        primary = run(client, "uci -q get podkop.main.interface || echo awg2").strip()
        return PathResult(
            policy="podkop (fake-IP DNS)",
            iface="podkop",
            detail=f"sing-box tproxy → bind {primary}",
        )

    if ip_in_podkop_subnets(client, dst_ip):
        primary = run(client, "uci -q get podkop.main.interface || echo awg2").strip()
        return PathResult(
            policy="podkop (community list subnet)",
            iface="podkop",
            detail=f"sing-box tproxy → bind {primary}",
        )

    for rule in rules:
        if rule.src and rule.src != client_ip:
            continue

        matched = False
        if rule.dst_kind == "any":
            matched = True
        elif rule.dst_kind == "cidrs":
            matched = ip_in_cidrs(dst_ip, rule.dst_value)
        elif rule.dst_kind == "set":
            matched = ip_in_nft_set(client, rule.dst_value, dst_ip)

        if not matched:
            continue

        iface = MARK_TO_IFACE.get(rule.mark, f"mark 0x{rule.mark:x}")
        return PathResult(policy=rule.comment, iface=iface, detail=f"fwmark 0x{rule.mark:06x}")

    route = run(client, f"ip route get {shlex.quote(dst_ip)} from {shlex.quote(client_ip)} iif br-lan 2>/dev/null || true")
    dev_match = re.search(r"\bdev\s+(\S+)", route)
    dev = dev_match.group(1) if dev_match else "wan"
    return PathResult(policy="default (no pbr match)", iface=dev, detail=route.splitlines()[0] if route else "main table")


def benchmark_iface(client: paramiko.SSHClient, iface: str, url: str) -> tuple[float | None, str]:
    cmd = (
        f"curl -sS -o /dev/null -w '%{{speed_download}} %{{time_total}} %{{http_code}}' "
        f"--interface {shlex.quote(iface)} --max-time 25 {shlex.quote(url)} 2>/dev/null || echo FAIL"
    )
    output = run(client, cmd, timeout=35)
    if output == "FAIL" or not output:
        return None, "FAIL"
    parts = output.split()
    if len(parts) < 3 or parts[2] != "200":
        return None, output
    speed = float(parts[0])
    elapsed = float(parts[1])
    return speed, f"{speed / 1024 / 1024:.2f} MiB/s in {elapsed:.1f}s"


def live_steam_connections(client: paramiko.SSHClient, client_ip: str) -> list[str]:
    output = run(
        client,
        f"conntrack -L 2>/dev/null | grep '{client_ip}' | grep -E ':443|:270|steam' | head -15 || true",
    )
    return [line for line in output.splitlines() if line.strip()]


def human_iface(label_iface: str) -> str:
    return IFACE_EGRESS.get(label_iface, label_iface)


def main() -> int:
    parser = argparse.ArgumentParser(description="Steam routing check and optional CDN speed compare")
    parser.add_argument(
        "--client-ip",
        default=os.environ.get("STEAM_CLIENT_IP", "192.168.1.133"),
        help="LAN client IP (default: pundef-pc .133)",
    )
    parser.add_argument(
        "--benchmark",
        action="store_true",
        help="Download a small Steam CDN file via wan/awg1/awg2 and compare speed",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="Show active conntrack sessions for the client (run while Steam downloads)",
    )
    args = parser.parse_args()

    client = connect()
    try:
        host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
        primary = run(client, "uci -q get podkop.main.interface || echo awg2").strip()
        nft_chain = run(client, "nft list chain inet fw4 pbr_prerouting 2>/dev/null || true")
        rules = parse_pbr_rules(nft_chain)

        print(f"OpenWrt {host} | client {args.client_ip} | primary tunnel: {primary}")
        print()

        print("=== Steam DNS and routing ===")
        all_ips: dict[str, list[str]] = {}
        path_by_ip: dict[str, PathResult] = {}

        for domain in STEAM_DOMAINS:
            ips = resolve_domain(client, domain)
            all_ips[domain] = ips
            if not ips:
                print(f"  {domain}: no A record")
                continue
            for ip_text in ips:
                path = evaluate_path(client, rules, args.client_ip, ip_text)
                path_by_ip[ip_text] = path
                print(f"  {domain} -> {ip_text}")
                print(f"    policy: {path.policy}")
                print(f"    exit:   {human_iface(path.iface)}")

        print()
        print("=== Summary ===")
        ifaces = {p.iface for p in path_by_ip.values()}
        if not path_by_ip:
            print("  No Steam IPs resolved — check router DNS.")
        elif len(ifaces) == 1:
            only = next(iter(ifaces))
            print(f"  Steam from {args.client_ip} currently exits via: {human_iface(only)}")
        else:
            print(f"  Mixed paths: {', '.join(sorted(human_iface(i) for i in ifaces))}")

        games_rule = next((r for r in rules if "games via" in r.comment and r.src == args.client_ip), None)
        if games_rule:
            print(
                f"  Games catch-all: \"{games_rule.comment}\" -> "
                f"{human_iface(MARK_TO_IFACE.get(games_rule.mark, '?'))}"
            )
            print("  (exceptions: Nexus -> WAN, kpb.lt -> workvpn)")

        if args.live:
            print()
            print("=== Active client connections (443/Steam) ===")
            lines = live_steam_connections(client, args.client_ip)
            if not lines:
                print("  Nothing found. Start a Steam download and re-run with --live")
            else:
                for line in lines:
                    print(f"  {line}")

        if args.benchmark:
            print()
            print(f"=== CDN speed test ({BENCHMARK_URL}) ===")
            results: list[tuple[str, float, str]] = []
            for iface in ("wan", "awg2", "awg1"):
                speed, text = benchmark_iface(client, iface, BENCHMARK_URL)
                status = text if speed is None else text
                print(f"  {iface:5} ({human_iface(iface)}): {status}")
                if speed is not None:
                    results.append((iface, speed, text))

            if results:
                best_iface, _best_speed, best_text = max(results, key=lambda item: item[1])
                print()
                print(f"  Fastest: {best_iface} - {best_text}")
                current_ifaces = {p.iface for p in path_by_ip.values()} - {"podkop", "workvpn"}
                if current_ifaces:
                    current = next(iter(current_ifaces))
                    if current != best_iface:
                        print(f"  Steam uses {current}, but {best_iface} was faster in this test.")
                        print("  Run: py -3 scripts/openwrt/switch_steam_route.py wan")
                    else:
                        print("  Current route matches the fastest path in this test.")
            else:
                print("  Benchmark failed (curl or tunnel down?).")

    finally:
        client.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
