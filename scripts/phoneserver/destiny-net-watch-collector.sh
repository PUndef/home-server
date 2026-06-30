#!/bin/sh
# Run Destiny conntrack watcher on phoneserver and publish logs to static-sites.

set -eu

ENV_FILE="/etc/routing-status-collector.env"
if [ -f "${ENV_FILE}" ]; then
  # shellcheck disable=SC1091
  . "${ENV_FILE}"
fi

: "${OPENWRT_HOST:=192.168.1.1}"
: "${OPENWRT_KEY:?OPENWRT_KEY required}"
: "${LXC_TARGET:=deploy@192.168.50.35}"
: "${LXC_KEY:?LXC_KEY required}"
: "${LXC_DIR:=/srv/static-sites/network-routing}"
: "${DESTINY_CLIENT_IP:=192.168.1.208}"
: "${DESTINY_WATCH_INTERVAL:=5}"
: "${DESTINY_PUBLISH_INTERVAL:=15}"

INSTALL_ROOT="${INSTALL_ROOT:-/opt/home-server}"
WATCH_PY="${INSTALL_ROOT}/scripts/openwrt/watch_destiny_sessions.py"
MANIFEST="${INSTALL_ROOT}/config/openwrt/overrides.json"
LOG_DIR="${DESTINY_LOG_DIR:-/var/lib/destiny-net-watch}"
PUBLISH_DIR="/tmp/destiny-net-watch-publish"
REMOTE_DIR="${LXC_DIR}/destiny"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o BatchMode=yes"

if [ ! -f "${WATCH_PY}" ]; then
  echo "missing ${WATCH_PY}" >&2
  exit 1
fi

mkdir -p "${LOG_DIR}" "${PUBLISH_DIR}"
export OPENWRT_HOST OPENWRT_KEY

# watch_destiny_sessions.py reads the manifest from repo-relative config/openwrt.
cd "${INSTALL_ROOT}"

python3 "${WATCH_PY}" \
  --client-ip "${DESTINY_CLIENT_IP}" \
  --interval "${DESTINY_WATCH_INTERVAL}" \
  --log-dir "${LOG_DIR}" \
  --allow-idle &
watch_pid="$!"

cleanup() {
  kill "${watch_pid}" 2>/dev/null || true
  wait "${watch_pid}" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

while true; do
  today="$(date +%F)"
  daily_log="${LOG_DIR}/${today}.jsonl"
  alerts_log="${LOG_DIR}/alerts.jsonl"
  latest_json="${PUBLISH_DIR}/destiny-watch.json"

  touch "${daily_log}" "${alerts_log}"

  python3 - "${daily_log}" "${alerts_log}" "${latest_json}" "${DESTINY_CLIENT_IP}" "${MANIFEST}" <<'PY'
import hashlib
import json
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

daily = Path(sys.argv[1])
alerts_path = Path(sys.argv[2])
out = Path(sys.argv[3])
client_ip = sys.argv[4]
manifest_path = Path(sys.argv[5])


def load_jsonl(path: Path) -> list[dict]:
    rows = []
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def manifest_version(path: Path) -> str:
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
        payload = {
            "destiny_activity": manifest["zapret_bypass"]["destiny_activity"],
            "destiny_steam_sdr": manifest["zapret_bypass"]["destiny_steam_sdr"],
        }
        raw = json.dumps(payload, sort_keys=True, separators=(",", ":")).encode("utf-8")
        return hashlib.sha256(raw).hexdigest()[:12]
    except Exception:
        return ""


ticks = load_jsonl(daily)
alert_ticks = load_jsonl(alerts_path)
last_tick = ticks[-1] if ticks else {}
counter = Counter()
for tick in ticks:
    for alert in tick.get("alerts", []):
        key = f"{alert.get('remote_ip')}:{alert.get('remote_port')}/{alert.get('proto')} ({alert.get('reason', '')})"
        counter[key] += 1

summary = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "client_ip": client_ip,
    "bypass_version": manifest_version(manifest_path),
    "daily_log": daily.name,
    "ticks": len(ticks),
    "alert_ticks": len(alert_ticks),
    "last_tick": {
        "timestamp": last_tick.get("timestamp"),
        "entry_count": last_tick.get("entry_count", 0),
        "gameish_count": last_tick.get("gameish_count", 0),
        "alert_count": len(last_tick.get("alerts", [])),
        "error": last_tick.get("error", ""),
    },
    "top_alerts": [{"target": target, "count": count} for target, count in counter.most_common(20)],
}
out.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  ssh ${SSH_OPTS} -i "${LXC_KEY}" "${LXC_TARGET}" "mkdir -p '${REMOTE_DIR}'"
  scp ${SSH_OPTS} -i "${LXC_KEY}" "${latest_json}" "${LXC_TARGET}:${REMOTE_DIR}/destiny-watch.json"
  scp ${SSH_OPTS} -i "${LXC_KEY}" "${daily_log}" "${LXC_TARGET}:${REMOTE_DIR}/${today}.jsonl"
  scp ${SSH_OPTS} -i "${LXC_KEY}" "${alerts_log}" "${LXC_TARGET}:${REMOTE_DIR}/alerts.jsonl"

  sleep "${DESTINY_PUBLISH_INTERVAL}"
done
