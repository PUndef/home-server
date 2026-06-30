"""Background Destiny network watcher — polls router nf_conntrack (read-only).

Run before gaming; keeps logging until Ctrl+C. On cabbage/weasel, inspect alerts.jsonl
or run analyze_destiny_log.py.

Usage:
  py -3 scripts/openwrt/watch_destiny_sessions.py
  py -3 scripts/openwrt/watch_destiny_sessions.py --client-ip 192.168.1.208 --interval 5
  py -3 scripts/openwrt/watch_destiny_sessions.py --once --verbose

Environment: OPENWRT_HOST, OPENWRT_USER, OPENWRT_KEY
"""

from __future__ import annotations

import argparse
import atexit
import ipaddress
import json
import os
import re
import shlex
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import paramiko

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_MANIFEST = ROOT / "config" / "openwrt" / "overrides.json"
DEFAULT_LOG_DIR = ROOT / "logs" / "destiny-net-watch"
LOCK_FILE = DEFAULT_LOG_DIR / ".watch.lock"

CONNTRACK_LINE = re.compile(
    r"^(?:ipv4|ipv6)\s+\d+\s+(?P<proto>\S+)\s+\d+\s+\d+\s+\S+\s+"
    r"src=(?P<src>[\d.]+)\s+dst=(?P<dst>[\d.]+)\s+"
    r"sport=(?P<sport>\d+)\s+dport=(?P<dport>\d+)"
)

FAKE_IP_NET = ipaddress.ip_network("198.18.0.0/15")
LAN_NET = ipaddress.ip_network("192.168.0.0/16")
STUN_UDP_PORT = 3478
GAME_TCP_PORTS = frozenset({7500, 7777, 8080})


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


def run(client: paramiko.SSHClient, command: str, timeout: int = 30) -> str:
    _stdin, stdout, stderr = client.exec_command(command, timeout=timeout)
    out = stdout.read().decode("utf-8", errors="ignore")
    err = stderr.read().decode("utf-8", errors="ignore")
    return (out + ("\n" + err if err else "")).strip()


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if sys.platform == "win32":
        result = subprocess.run(
            ["tasklist", "/FI", f"PID eq {pid}", "/NH"],
            capture_output=True,
            text=True,
            check=False,
        )
        return str(pid) in result.stdout
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def acquire_lock(lock_path: Path) -> None:
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if lock_path.exists():
        try:
            data = json.loads(lock_path.read_text(encoding="utf-8"))
            old_pid = int(data.get("pid", 0))
        except (json.JSONDecodeError, ValueError, OSError):
            old_pid = 0
        if old_pid and pid_alive(old_pid):
            print(f"Watcher already running (PID {old_pid}). Stop it first:", file=sys.stderr)
            print(f"  .\\scripts\\openwrt\\stop-destiny-net-watch.ps1", file=sys.stderr)
            raise SystemExit(1)
        lock_path.unlink(missing_ok=True)

    payload = {
        "pid": os.getpid(),
        "started": datetime.now(timezone.utc).isoformat(),
    }
    lock_path.write_text(json.dumps(payload), encoding="utf-8")

    def _release() -> None:
        try:
            if lock_path.exists():
                data = json.loads(lock_path.read_text(encoding="utf-8"))
                if int(data.get("pid", 0)) == os.getpid():
                    lock_path.unlink(missing_ok=True)
        except (json.JSONDecodeError, ValueError, OSError):
            lock_path.unlink(missing_ok=True)

    atexit.register(_release)


def load_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_destiny_nets(manifest: dict[str, Any]) -> list[ipaddress._BaseNetwork]:  # noqa: SLF001
    raw = manifest["zapret_bypass"]["destiny_activity"]["dst"]
    return [ipaddress.ip_network(item, strict=False) for item in raw]


def load_forbidden_nets(manifest: dict[str, Any]) -> list[ipaddress._BaseNetwork]:  # noqa: SLF001
    raw = manifest["zapret_bypass"]["destiny_activity"]["forbidden"]
    return [ipaddress.ip_network(item, strict=False) for item in raw]


def parse_sdr_port_range(manifest: dict[str, Any]) -> tuple[int, int]:
    spec = manifest["zapret_bypass"]["destiny_steam_sdr"]["udp_dport"]
    start_s, end_s = spec.split("-", maxsplit=1)
    return int(start_s), int(end_s)


def ip_in_nets(ip_text: str, nets: list[ipaddress._BaseNetwork]) -> bool:  # noqa: SLF001
    ip = ipaddress.ip_address(ip_text)
    return any(ip in net for net in nets)


def parse_conntrack(text: str, client_ip: str) -> list[dict[str, Any]]:
    entries: list[dict[str, Any]] = []
    for line in text.splitlines():
        if client_ip not in line:
            continue
        match = CONNTRACK_LINE.search(line)
        if not match:
            continue
        groups = match.groupdict()
        if groups["src"] != client_ip and groups["dst"] != client_ip:
            continue
        remote_ip = groups["dst"] if groups["src"] == client_ip else groups["src"]
        remote_port = int(groups["dport"] if groups["src"] == client_ip else groups["sport"])
        local_port = int(groups["sport"] if groups["src"] == client_ip else groups["dport"])
        entries.append(
            {
                "proto": groups["proto"],
                "remote_ip": remote_ip,
                "remote_port": remote_port,
                "local_port": local_port,
                "raw": line.strip()[:240],
            }
        )
    return entries


def classify_entry(
    entry: dict[str, Any],
    destiny_nets: list[ipaddress._BaseNetwork],  # noqa: SLF001
    forbidden_nets: list[ipaddress._BaseNetwork],  # noqa: SLF001
    sdr_lo: int,
    sdr_hi: int,
) -> tuple[str, str | None]:
    remote_ip = entry["remote_ip"]
    proto = entry["proto"].lower()
    remote_port = entry["remote_port"]

    if ip_in_nets(remote_ip, [LAN_NET, FAKE_IP_NET]):
        return "local_or_fake", None

    if ip_in_nets(remote_ip, forbidden_nets):
        return "discord_voice_range", None

    if ip_in_nets(remote_ip, destiny_nets):
        return "destiny_bypass", None

    if proto == "udp" and sdr_lo <= remote_port <= sdr_hi:
        return "steam_sdr_bypass", None

    if remote_port == 53:
        return "dns", None

    if remote_port in (443, 80) and proto == "tcp":
        return "http_tls", None

    if proto == "udp" and remote_port == STUN_UDP_PORT:
        return "stun", None

    if proto == "udp":
        return "zapret_udp", "udp_outside_destiny_bypass"

    if proto == "tcp" and remote_port in GAME_TCP_PORTS:
        return "game_tcp", "tcp_game_port_outside_bypass"

    if proto == "tcp":
        return "tcp_other", None

    return "other", None


def collect_tick(
    client: paramiko.SSHClient,
    client_ip: str,
    destiny_nets: list[ipaddress._BaseNetwork],  # noqa: SLF001
    forbidden_nets: list[ipaddress._BaseNetwork],  # noqa: SLF001
    sdr_lo: int,
    sdr_hi: int,
) -> dict[str, Any]:
    raw = run(
        client,
        f"grep {shlex.quote(client_ip)} /proc/net/nf_conntrack 2>/dev/null || true",
    )
    entries = parse_conntrack(raw, client_ip)

    classified: list[dict[str, Any]] = []
    alerts: list[dict[str, Any]] = []
    for entry in entries:
        bucket, alert_reason = classify_entry(entry, destiny_nets, forbidden_nets, sdr_lo, sdr_hi)
        item = {**entry, "bucket": bucket}
        classified.append(item)
        if alert_reason:
            alerts.append({**item, "reason": alert_reason})

    gameish = [e for e in classified if e["bucket"] in {"destiny_bypass", "steam_sdr_bypass", "zapret_udp", "game_tcp"}]

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "client_ip": client_ip,
        "entry_count": len(classified),
        "gameish_count": len(gameish),
        "alerts": alerts,
        "entries": classified,
    }


def client_neigh_state(client: paramiko.SSHClient, client_ip: str) -> str:
    output = run(client, f"ip neigh show {shlex.quote(client_ip)} 2>/dev/null || true")
    if not output:
        return "missing"
    if "REACHABLE" in output:
        return "REACHABLE"
    if "STALE" in output:
        return "STALE"
    if "DELAY" in output or "PROBE" in output:
        return "STALE"
    return output.split()[-1] if output.split() else "unknown"


def preflight(client: paramiko.SSHClient, client_ip: str) -> dict[str, Any]:
    host = os.environ.get("OPENWRT_HOST", "192.168.1.1")
    print(f"Preflight | router={host} | client={client_ip}")

    proc_check = run(client, "test -r /proc/net/nf_conntrack && echo OK || echo FAIL")
    if "OK" not in proc_check:
        print("FAIL: /proc/net/nf_conntrack not readable on router", file=sys.stderr)
        raise SystemExit(2)

    conntrack_cli = run(client, "which conntrack 2>/dev/null || true")
    if conntrack_cli:
        print(f"Note: conntrack CLI exists ({conntrack_cli}) but watcher uses /proc/net/nf_conntrack")

    neigh = client_neigh_state(client, client_ip)
    print(f"Neigh state: {neigh}")

    return {"neigh": neigh}


def validate_probe(probe: dict[str, Any], neigh: str) -> None:
    count = probe["entry_count"]
    if count > 0:
        print(f"OK: probe saw {count} conntrack entries")
        return

    if neigh in {"missing", "FAILED", "unknown"}:
        print(
            f"FAIL: 0 conntrack entries and client not reachable on LAN (neigh={neigh})",
            file=sys.stderr,
        )
        print("Check --client-ip or connect PC to Wi-Fi/eth.", file=sys.stderr)
        raise SystemExit(2)

    print(
        "FAIL: client reachable but 0 conntrack entries — refusing blind log",
        file=sys.stderr,
    )
    print("Open a browser/YouTube tab or wait for traffic, then retry.", file=sys.stderr)
    raise SystemExit(2)


def compact_tick(tick: dict[str, Any], verbose: bool) -> dict[str, Any]:
    if verbose or tick.get("alerts") or tick.get("error"):
        return tick
    return {
        "timestamp": tick["timestamp"],
        "client_ip": tick["client_ip"],
        "entry_count": tick["entry_count"],
        "gameish_count": tick["gameish_count"],
        "alerts": tick["alerts"],
    }


def log_path_for_today(log_dir: Path) -> Path:
    day = datetime.now().strftime("%Y-%m-%d")
    return log_dir / f"{day}.jsonl"


def append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")


def print_tick_summary(tick: dict[str, Any]) -> None:
    ts = tick["timestamp"]
    if tick.get("error"):
        print(f"{ts} | ERROR {tick['error']}")
        return
    alerts = tick.get("alerts", [])
    gameish = tick.get("gameish_count", 0)
    total = tick.get("entry_count", 0)
    if alerts:
        uniq = sorted({f"{a['remote_ip']}:{a['remote_port']}/{a['proto']}" for a in alerts})
        print(f"{ts} | entries={total} gameish={gameish} ALERT {len(alerts)} -> {', '.join(uniq)}")
        return
    print(f"{ts} | entries={total} gameish={gameish}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Poll router nf_conntrack while Destiny runs")
    parser.add_argument("--client-ip", default=os.environ.get("DESTINY_CLIENT_IP", "192.168.1.208"))
    parser.add_argument("--interval", type=int, default=5, help="Seconds between polls (default: 5)")
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR)
    parser.add_argument("--once", action="store_true", help="Single snapshot, then exit")
    parser.add_argument("--verbose", action="store_true", help="Log full entries every tick")
    parser.add_argument("--no-lock", action="store_true", help="Skip single-instance lock (debug)")
    args = parser.parse_args()

    if not args.once and not args.no_lock:
        acquire_lock(LOCK_FILE if args.log_dir == DEFAULT_LOG_DIR else args.log_dir / ".watch.lock")

    manifest = load_manifest(DEFAULT_MANIFEST)
    destiny_nets = load_destiny_nets(manifest)
    forbidden_nets = load_forbidden_nets(manifest)
    sdr_lo, sdr_hi = parse_sdr_port_range(manifest)

    log_file = log_path_for_today(args.log_dir)
    alerts_file = args.log_dir / "alerts.jsonl"

    print(f"Destiny net watch | client={args.client_ip} | interval={args.interval}s")
    print(f"Log: {log_file}")
    print(f"Alerts: {alerts_file}")
    print("ALERT = game UDP/TCP outside DESTINY_NETS bypass (cabbage/weasel suspect)")
    print("Stop: Ctrl+C or stop-destiny-net-watch.ps1")
    print()

    client = connect()
    try:
        pf = preflight(client, args.client_ip)
        probe = collect_tick(client, args.client_ip, destiny_nets, forbidden_nets, sdr_lo, sdr_hi)
        validate_probe(probe, pf["neigh"])
        print()

        while True:
            try:
                tick = collect_tick(client, args.client_ip, destiny_nets, forbidden_nets, sdr_lo, sdr_hi)
            except Exception as exc:  # noqa: BLE001
                tick = {
                    "timestamp": datetime.now(timezone.utc).isoformat(),
                    "client_ip": args.client_ip,
                    "error": str(exc),
                    "entry_count": 0,
                    "gameish_count": 0,
                    "alerts": [],
                    "entries": [],
                }
                try:
                    client.close()
                except Exception:  # noqa: BLE001
                    pass
                time.sleep(2)
                client = connect()

            record = compact_tick(tick, args.verbose)
            append_jsonl(log_file, record)
            if tick.get("alerts"):
                append_jsonl(alerts_file, tick)
            print_tick_summary(tick)

            if args.once:
                break
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nStopped.")
        return 0
    finally:
        client.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
