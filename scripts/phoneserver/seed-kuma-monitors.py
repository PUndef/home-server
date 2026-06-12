#!/usr/bin/env python3
"""Seed Uptime Kuma monitors from kuma-monitors.json (idempotent by monitor name).

Requires: venv at scripts/phoneserver/.venv-kuma (created by seed-kuma-monitors.sh)
Package: uptime-kuma-api-v2 (Kuma 2.x; lucasheld/uptime-kuma-api is 1.x only)

Env:
  KUMA_URL       default http://192.168.50.35:3001
  KUMA_USERNAME  admin login (required)
  KUMA_PASSWORD  admin password (required)

Usage:
  KUMA_USERNAME=admin KUMA_PASSWORD='...' python3 seed-kuma-monitors.py
  python3 seed-kuma-monitors.py --dry-run
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

try:
    from uptime_kuma_api import MonitorType, UptimeKumaApi
except ImportError:
    print("missing package: pip install uptime-kuma-api-v2", file=sys.stderr)
    sys.exit(2)

TYPE_MAP = {
    "http": MonitorType.HTTP,
    "ping": MonitorType.PING,
    "port": MonitorType.PORT,
    "group": MonitorType.GROUP,
}

DEFAULT_CONFIG = Path(__file__).with_name("kuma-monitors.json")


def monitor_id(res: dict) -> int:
    return int(res.get("monitorId") or res["monitorID"])


def load_config(path: Path) -> dict:
    with path.open(encoding="utf-8") as f:
        return json.load(f)


def existing_names(api: UptimeKumaApi) -> set[str]:
    return {m.get("name", "") for m in api.get_monitors()}


def ensure_groups(api: UptimeKumaApi, names: list[str], have: set[str], dry_run: bool) -> dict[str, int]:
    group_ids: dict[str, int] = {}
    for name in names:
        if name in have:
            for m in api.get_monitors():
                if m.get("name") == name and m.get("type") == MonitorType.GROUP:
                    group_ids[name] = m["id"]
                    break
            continue
        if dry_run:
            print(f"[dry-run] add group: {name}")
            continue
        res = api.add_monitor(type=MonitorType.GROUP, name=name, conditions=[])
        group_ids[name] = monitor_id(res)
        have.add(name)
        print(f"added group: {name} (id={group_ids[name]})")
    if not dry_run:
        for m in api.get_monitors():
            if m.get("type") == MonitorType.GROUP and m.get("name") in names:
                group_ids[m["name"]] = m["id"]
    return group_ids


def seed_one_monitor(
    api: UptimeKumaApi,
    spec: dict,
    group_ids: dict[str, int],
    have: set[str],
    dry_run: bool,
) -> None:
    name = spec["name"]
    if name in have:
        print(f"skip (exists): {name}")
        return

    mtype = TYPE_MAP[spec["type"]]
    kwargs: dict = {
        "type": mtype,
        "name": name,
        "interval": spec.get("interval", 60),
        "conditions": [],
    }
    if spec.get("maxretries") is not None:
        kwargs["maxretries"] = spec["maxretries"]
    if spec.get("ignoreTls") is not None:
        kwargs["ignoreTls"] = spec["ignoreTls"]
    if spec.get("acceptedStatusCodes") is not None:
        kwargs["accepted_statuscodes"] = spec["acceptedStatusCodes"]
    if spec.get("group") and spec["group"] in group_ids:
        kwargs["parent"] = group_ids[spec["group"]]

    if mtype == MonitorType.HTTP:
        kwargs["url"] = spec["url"]
    elif mtype == MonitorType.PING:
        kwargs["hostname"] = spec["hostname"]
    elif mtype == MonitorType.PORT:
        kwargs["hostname"] = spec["hostname"]
        kwargs["port"] = spec["port"]
    else:
        raise ValueError(f"unsupported type in spec: {spec}")

    if dry_run:
        print(f"[dry-run] add {spec['type']}: {name}")
        return

    res = api.add_monitor(**kwargs)
    have.add(name)
    print(f"added: {name} (id={monitor_id(res)})")


def main() -> int:
    parser = argparse.ArgumentParser(description="Seed Uptime Kuma monitors")
    parser.add_argument(
        "--config",
        type=Path,
        default=DEFAULT_CONFIG,
        help=f"monitor list JSON (default: {DEFAULT_CONFIG.name})",
    )
    parser.add_argument("--dry-run", action="store_true", help="print actions only")
    args = parser.parse_args()

    url = os.environ.get("KUMA_URL", "http://192.168.50.35:3001")
    user = os.environ.get("KUMA_USERNAME")
    password = os.environ.get("KUMA_PASSWORD")
    if not user or not password:
        print("set KUMA_USERNAME and KUMA_PASSWORD", file=sys.stderr)
        return 2

    cfg = load_config(args.config)
    api = UptimeKumaApi(url, timeout=30)
    api.login(user, password)
    try:
        have = existing_names(api)
        group_ids = ensure_groups(api, cfg.get("groups", []), have, args.dry_run)
        for spec in cfg.get("monitors", []):
            seed_one_monitor(api, spec, group_ids, have, args.dry_run)
    finally:
        api.disconnect()

    print("done")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
