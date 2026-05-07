"""Trace how OpenWrt would handle a domain or IP in the current routing stack.

Environment:
- OPENWRT_HOST (default: 192.168.1.1)
- OPENWRT_USER (default: root)
- OPENWRT_KEY  (default: C:\\Users\\PUndef-PC\\.ssh\\openwrt_ax300t_nopass)
"""

from __future__ import annotations

import ipaddress
import os
import re
import shlex
import sys
from dataclasses import dataclass

import paramiko


FAKE_IP_NET = ipaddress.ip_network("198.18.0.0/15")
PODKOP_MARK = "0x00100000"
PBR_AWG1_MARK = "0x00020000"


@dataclass(frozen=True)
class RouteInfo:
    raw: str
    dev: str
    table: str


@dataclass(frozen=True)
class TraceContext:
    podkop_status: str
    podkop_subnets: str
    podkop_table: str
    pbr_chain: str
    zapret_table: str


def load_private_key(key_path: str) -> paramiko.PKey:
    last_error: Exception | None = None
    key_classes = (paramiko.Ed25519Key, paramiko.RSAKey, paramiko.ECDSAKey)
    for key_cls in key_classes:
        try:
            return key_cls.from_private_key_file(key_path)
        except paramiko.SSHException as exc:
            last_error = exc

    raise last_error or paramiko.SSHException("Unsupported private key type")


def run_command(client: paramiko.SSHClient, command: str, timeout: int = 60) -> str:
    stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    _ = stdin
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    combined = (out + ("\n" + err if err else "")).strip()
    return combined


def is_ipv4(value: str) -> bool:
    try:
        ipaddress.ip_address(value)
    except ValueError:
        return False
    return "." in value


def parse_resolved_ipv4(nslookup_output: str) -> list[str]:
    addresses: list[str] = []
    for line in nslookup_output.splitlines():
        match = re.search(r"Address(?:\s+\d+)?:\s*([0-9]+(?:\.[0-9]+){3})(?:\s|$)", line)
        if not match:
            continue
        ip = match.group(1)
        if ip == "192.168.1.1":
            continue
        if ip not in addresses:
            addresses.append(ip)
    return addresses


def parse_route(route_output: str) -> RouteInfo:
    first_line = route_output.splitlines()[0] if route_output else ""
    dev_match = re.search(r"\bdev\s+(\S+)", first_line)
    table_match = re.search(r"\btable\s+(\S+)", first_line)
    return RouteInfo(
        raw=route_output.strip() or "no route output",
        dev=dev_match.group(1) if dev_match else "",
        table=table_match.group(1) if table_match else "main",
    )


def iter_ipv4_patterns(text: str) -> list[str]:
    # Matches single IPv4, CIDR, and nft interval ranges like 91.108.4.0-91.108.23.255.
    pattern = r"\b[0-9]+(?:\.[0-9]+){3}(?:/[0-9]+|-[0-9]+(?:\.[0-9]+){3})?\b"
    return re.findall(pattern, text)


def ip_matches_patterns(ip_text: str, patterns: list[str]) -> bool:
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


def has_zapret_wan_postnat(zapret_table: str) -> bool:
    return 'elements = { "wan" }' in zapret_table and "oifname @wanif" in zapret_table


def collect_context(client: paramiko.SSHClient) -> TraceContext:
    return TraceContext(
        podkop_status=run_command(client, "/usr/bin/podkop get_status 2>/dev/null || true"),
        podkop_subnets=run_command(client, "nft list set inet PodkopTable podkop_subnets 2>/dev/null || true"),
        podkop_table=run_command(client, "nft list table inet PodkopTable 2>/dev/null || true"),
        pbr_chain=run_command(client, "nft list chain inet fw4 pbr_prerouting 2>/dev/null || true"),
        zapret_table=run_command(client, "nft list table inet zapret 2>/dev/null || true"),
    )


def resolve_target(client: paramiko.SSHClient, target: str) -> list[str]:
    if is_ipv4(target):
        return [target]

    output = run_command(client, f"nslookup {shlex.quote(target)} 192.168.1.1")
    return parse_resolved_ipv4(output)


def trace_ip(client: paramiko.SSHClient, ctx: TraceContext, ip_text: str) -> None:
    ip = ipaddress.ip_address(ip_text)
    pbr_patterns = iter_ipv4_patterns(ctx.pbr_chain)
    podkop_patterns = iter_ipv4_patterns(ctx.podkop_subnets)

    fake_ip = ip in FAKE_IP_NET
    pbr_match = ip_matches_patterns(ip_text, pbr_patterns)
    podkop_match = fake_ip or ip_matches_patterns(ip_text, podkop_patterns)
    zapret_wan = has_zapret_wan_postnat(ctx.zapret_table)

    route_normal = parse_route(run_command(client, f"ip route get {shlex.quote(ip_text)} 2>/dev/null || true"))
    route_pbr = parse_route(run_command(client, f"ip route get {shlex.quote(ip_text)} mark 0x20000 2>/dev/null || true"))

    print(f"\nIP: {ip_text}")
    print(f"  DNS/fake-ip: {'yes, 198.18.0.0/15' if fake_ip else 'no'}")
    print(f"  pbr match: {'yes' if pbr_match else 'no'}")
    print(f"  podkop match: {'yes' if podkop_match else 'no'}")
    print(f"  normal route: {route_normal.raw}")
    print(f"  pbr-mark route: {route_pbr.raw}")

    if podkop_match:
        reason = "DNS fake-ip 198.18.0.0/15" if fake_ip else "podkop_subnets match"
        print("  PATH:")
        print(f"    {reason}")
        print("    -> normal route above is not the final path: tproxy intercepts before that")
        print(f"    -> PodkopTable mangle sets fwmark {PODKOP_MARK}")
        print("    -> PodkopTable proxy tproxy to 127.0.0.1:1602")
        print("    -> local sing-box creates outbound connection")
        print("    -> expected exit: awg1")
        return

    if pbr_match:
        print("  PATH:")
        print("    pbr_prerouting destination match")
        print(f"    -> pbr_mark_0x020000 sets fwmark {PBR_AWG1_MARK}")
        print("    -> ip rule priority 29999 lookup pbr_awg1")
        print("    -> expected exit: awg1")
        return

    if route_normal.dev == "awg1":
        print("  PATH:")
        print("    no pbr/podkop match detected")
        print("    -> main/static route already points to awg1")
        print("    -> expected exit: awg1")
        return

    if route_normal.dev == "wan":
        print("  PATH:")
        print("    no pbr/podkop match detected")
        print("    -> ip rule falls back to main table")
        print("    -> default route dev wan")
        if zapret_wan:
            print("    -> zapret postnat may queue first WAN packets to nfqws")
        else:
            print("    -> zapret WAN postnat rule not detected")
        print("    -> expected exit: wan -> ASUS -> ISP")
        return

    print("  PATH:")
    print("    no pbr/podkop match detected")
    print(f"    -> route result is unclear: dev={route_normal.dev or 'unknown'} table={route_normal.table}")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: python scripts/openwrt/trace_traffic.py <domain-or-ip> [domain-or-ip ...]")
        return 2

    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    user = os.environ.get("OPENWRT_USER", "root")
    key_path = os.environ.get("OPENWRT_KEY", r"C:\Users\PUndef-PC\.ssh\openwrt_ax300t_nopass")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())

    try:
        key = load_private_key(key_path)
        client.connect(host, username=user, pkey=key, timeout=10)
    except Exception as exc:  # noqa: BLE001
        print(f"Connection error: {exc}")
        return 2

    try:
        ctx = collect_context(client)
        print(f"OpenWrt trace via {host}")
        print(f"podkop status: {ctx.podkop_status or 'unknown'}")

        for target in sys.argv[1:]:
            print(f"\nTARGET: {target}")
            ips = resolve_target(client, target)
            if not ips:
                print("  No IPv4 addresses resolved by router DNS.")
                continue
            for ip_text in ips:
                trace_ip(client, ctx, ip_text)
    finally:
        client.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
