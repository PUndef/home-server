"""Summarize Destiny net watch logs after cabbage/weasel.

Usage:
  py -3 scripts/openwrt/analyze_destiny_log.py
  py -3 scripts/openwrt/analyze_destiny_log.py --last 30
  py -3 scripts/openwrt/analyze_destiny_log.py --date 2026-06-30
"""

from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LOG_DIR = ROOT / "logs" / "destiny-net-watch"


def load_ticks(path: Path) -> list[dict]:
    if not path.exists():
        return []
    ticks: list[dict] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            ticks.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return ticks


def alert_key(alert: dict) -> str:
    return f"{alert['remote_ip']}:{alert['remote_port']}/{alert['proto']} ({alert.get('reason', '')})"


def main() -> int:
    parser = argparse.ArgumentParser(description="Analyze Destiny net watch logs")
    parser.add_argument("--log-dir", type=Path, default=DEFAULT_LOG_DIR)
    parser.add_argument("--date", default=datetime.now().strftime("%Y-%m-%d"))
    parser.add_argument("--last", type=int, default=20, help="Show last N tick summaries")
    args = parser.parse_args()

    log_file = args.log_dir / f"{args.date}.jsonl"
    alerts_file = args.log_dir / "alerts.jsonl"

    print(f"Daily log: {log_file}")
    print(f"Alerts log: {alerts_file}")
    print()

    ticks = load_ticks(log_file)
    if not ticks:
        print("No ticks found.")
        return 1

    print(f"Total ticks: {len(ticks)}")
    counter: Counter[str] = Counter()
    for tick in ticks:
        for alert in tick.get("alerts", []):
            counter[alert_key(alert)] += 1

    if counter:
        print("\nTop ALERT targets (all ticks):")
        for key, count in counter.most_common(25):
            print(f"  {count:4d}  {key}")
    else:
        print("\nNo ALERT entries in daily log.")

    print(f"\nLast {args.last} ticks:")
    for tick in ticks[-args.last :]:
        alerts = tick.get("alerts", [])
        uniq = sorted({f"{a['remote_ip']}:{a['remote_port']}/{a['proto']}" for a in alerts})
        err = tick.get("error", "")
        suffix = f" ALERT {uniq}" if uniq else (f" ERROR {err}" if err else "")
        print(
            f"  {tick.get('timestamp', '?')} "
            f"entries={tick.get('entry_count', 0)} "
            f"gameish={tick.get('gameish_count', 0)}{suffix}"
        )

    alert_ticks = load_ticks(alerts_file)
    if alert_ticks:
        print(f"\nAlerts-only log: {len(alert_ticks)} entries -> {alerts_file}")
        last = alert_ticks[-1]
        if last.get("alerts"):
            print("Last alert tick:")
            for alert in last["alerts"][:10]:
                print(f"  {alert_key(alert)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
