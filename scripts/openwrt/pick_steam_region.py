"""Pick a good Steam download region by probing Valve CDN servers.

Fetches content servers from Steam API for relevant cell IDs, resolves them
via router DNS, benchmarks connect/latency/download via WAN from OpenWrt,
and suggests a Steam client Download Region.

Usage:
  py -3 scripts/openwrt/pick_steam_region.py
  py -3 scripts/openwrt/pick_steam_region.py --quick
  py -3 scripts/openwrt/pick_steam_region.py --iface awg2

Environment: OPENWRT_HOST, OPENWRT_USER, OPENWRT_KEY
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field

import paramiko

STEAM_API = (
    "https://api.steampowered.com/IContentServerDirectoryService/"
    "GetServersForSteamPipe/v1/?cell_id={cell_id}&max_servers={max_servers}"
)

# cell_id -> label shown in Steam-ish wording (not all map 1:1 to UI anymore)
STEAM_REGIONS: dict[int, str] = {
    0: "Auto (geolocation)",
    7: "Russia - Moscow",
    27: "Russia - Yekaterinburg",
    38: "Poland - Warsaw",
    5: "Germany - Frankfurt",
    15: "Netherlands - Amsterdam",
    66: "Sweden - Stockholm",
    68: "Finland - Helsinki",
    92: "Austria - Vienna",
    149: "Russia - Moscow (edge 149)",
    150: "Russia - Moscow (edge 150)",
    151: "Russia - Moscow (edge 151)",
}

QUICK_CELL_IDS = (0, 7, 38, 5, 15, 66)
FULL_CELL_IDS = tuple(STEAM_REGIONS.keys())


@dataclass
class ServerProbe:
    host: str
    server_type: str
    cell_id: int | None
    load: int
    ip: str = ""
    connect_s: float | None = None
    speed_bps: float | None = None
    http_code: str = ""
    error: str = ""


@dataclass
class RegionResult:
    cell_id: int
    label: str
    servers: list[ServerProbe] = field(default_factory=list)
    best: ServerProbe | None = None
    score: float = float("inf")


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


def run(client: paramiko.SSHClient, command: str, timeout: int = 60) -> str:
    _stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return (out + ("\n" + err if err else "")).strip()


def fetch_servers(cell_id: int, max_servers: int = 12) -> list[dict]:
    url = STEAM_API.format(cell_id=cell_id, max_servers=max_servers)
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            data = json.load(resp)
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        print(f"  WARN: Steam API cell_id={cell_id}: {exc}", file=sys.stderr)
        return []
    return data.get("response", {}).get("servers", [])


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


def resolve_host(client: paramiko.SSHClient, host: str) -> str:
    output = run(client, f"nslookup {shlex.quote(host)} 192.168.1.1")
    ips = parse_resolved_ipv4(output)
    return ips[0] if ips else ""


def probe_host(client: paramiko.SSHClient, host: str, iface: str) -> tuple[float | None, float | None, str, str]:
    # First 16 KiB over HTTPS; many caches return 403/404 but connect + partial xfer still rank paths.
    cmd = (
        f"curl -sS -o /dev/null -w '%{{time_connect}} %{{speed_download}} %{{http_code}}' "
        f"--interface {shlex.quote(iface)} --max-time 12 -r 0-16383 "
        f"https://{shlex.quote(host)}/ 2>/dev/null || echo FAIL"
    )
    output = run(client, cmd, timeout=20)
    if output == "FAIL" or not output:
        return None, None, "", "curl failed"
    parts = output.split()
    if len(parts) < 3:
        return None, None, "", output
    http_code = parts[2]
    if http_code == "000" or "FAIL" in output:
        return None, None, http_code, "bad http code"
    try:
        connect_s = float(parts[0])
        speed_bps = float(parts[1])
    except ValueError:
        return None, None, http_code, output
    if connect_s <= 0:
        return None, None, http_code, "zero connect time"
    return connect_s, speed_bps, http_code, ""


def pick_servers(raw: list[dict], limit: int = 4) -> list[ServerProbe]:
    """Prefer Valve SteamCache hosts; fall back to mandatory-HTTPS CDNs."""
    chosen: list[ServerProbe] = []
    seen_hosts: set[str] = set()

    def add(entry: dict) -> None:
        host = entry.get("host", "")
        if not host or host in seen_hosts:
            return
        seen_hosts.add(host)
        chosen.append(
            ServerProbe(
                host=host,
                server_type=entry.get("type", "?"),
                cell_id=entry.get("cell_id"),
                load=int(entry.get("load", 0) or 0),
            )
        )

    for entry in raw:
        if entry.get("type") == "SteamCache":
            add(entry)
    for entry in raw:
        if entry.get("https_support") == "mandatory" and entry.get("type") != "SteamCache":
            add(entry)
    for entry in raw:
        add(entry)

    return chosen[:limit]


def score_probe(probe: ServerProbe) -> float:
    if probe.connect_s is None:
        return float("inf")
    # Lower is better: latency-heavy, speed as tiebreaker.
    speed_penalty = 0.0
    if probe.speed_bps and probe.speed_bps > 0:
        speed_penalty = 1.0 / probe.speed_bps
    load_penalty = probe.load / 1000.0
    return probe.connect_s + speed_penalty + load_penalty


def format_speed(bps: float | None) -> str:
    if bps is None or bps <= 0:
        return "n/a"
    mib = bps / 1024 / 1024
    if mib >= 1:
        return f"{mib:.2f} MiB/s"
    return f"{bps / 1024:.0f} KiB/s"


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe Steam CDN regions and suggest Download Region")
    parser.add_argument("--quick", action="store_true", help="Test fewer regions (faster)")
    parser.add_argument(
        "--iface",
        default="wan",
        help="Router egress interface for probes (default: wan)",
    )
    parser.add_argument(
        "--max-servers",
        type=int,
        default=12,
        help="Servers requested per cell from Steam API",
    )
    args = parser.parse_args()

    cell_ids = QUICK_CELL_IDS if args.quick else FULL_CELL_IDS
    client = connect()

    try:
        print(f"OpenWrt probes via {args.iface}")
        print("Steam API -> CDN hosts -> router DNS -> curl benchmark")
        print()

        region_results: list[RegionResult] = []

        for cell_id in cell_ids:
            label = STEAM_REGIONS.get(cell_id, f"cell {cell_id}")
            raw = fetch_servers(cell_id, max_servers=args.max_servers)
            servers = pick_servers(raw)
            if not servers:
                print(f"[{cell_id:3}] {label}: no servers from API")
                continue

            print(f"[{cell_id:3}] {label}")
            region = RegionResult(cell_id=cell_id, label=label)

            for srv in servers:
                srv.ip = resolve_host(client, srv.host)
                if not srv.ip:
                    srv.error = "no DNS"
                    print(f"      {srv.host}: no DNS")
                    continue

                connect_s, speed_bps, code, err = probe_host(client, srv.host, args.iface)
                srv.connect_s = connect_s
                srv.speed_bps = speed_bps
                srv.http_code = code
                srv.error = err

                if connect_s is None:
                    print(f"      {srv.host} ({srv.ip}): FAIL {err or code}")
                else:
                    print(
                        f"      {srv.host} ({srv.ip}): "
                        f"connect={connect_s:.3f}s speed={format_speed(speed_bps)} code={code}"
                    )
                region.servers.append(srv)

            ok = [s for s in region.servers if s.connect_s is not None]
            if ok:
                region.best = min(ok, key=score_probe)
                region.score = score_probe(region.best)
            region_results.append(region)
            print()

        ranked = [r for r in region_results if r.best is not None]
        ranked.sort(key=lambda r: r.score)

        print("=== Ranking (best probe per region) ===")
        if not ranked:
            print("No successful probes.")
            return 1

        for i, region in enumerate(ranked, 1):
            best = region.best
            assert best is not None
            print(
                f"  {i}. cell_id={region.cell_id} {region.label}\n"
                f"     {best.host} connect={best.connect_s:.3f}s speed={format_speed(best.speed_bps)}"
            )

        top = ranked[0]
        best = top.best
        assert best is not None

        print()
        print("=== Recommendation ===")
        print(f"  Steam Settings -> Downloads -> Download Region:")
        print(f"    try: {top.label}")
        print(f"    (cell_id={top.cell_id}, best server {best.host})")
        print()
        print("Notes:")
        print("  - Steam may ignore Download Region and pick servers by its own geo logic.")
        print("  - This test uses small HTTPS probes from the router, not a full game download.")
        print("  - Re-run after changing region, then compare real Steam download speed.")
        if args.iface == "wan":
            print("  - Probes used WAN; matches your current Steam pbr policy on .133.")
        else:
            print(f"  - Probes used {args.iface}; Steam from .133 may still exit via WAN pbr.")

        # Show what auto (0) picked vs best
        auto = next((r for r in region_results if r.cell_id == 0 and r.best), None)
        if auto and auto.best and top.cell_id != 0:
            print()
            print(
                f"  Auto (cell 0) best was {auto.best.host} connect={auto.best.connect_s:.3f}s; "
                f"manual {top.label} looks better in this test."
            )
        elif auto and auto.best and top.cell_id == 0:
            print()
            print("  Auto/geolocation already matches the best probe in this test.")

    finally:
        client.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
