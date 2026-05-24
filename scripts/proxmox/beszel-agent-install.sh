#!/usr/bin/env bash
# beszel-agent-install.sh
#
# Installs Beszel Agent natively (binary + systemd unit) on a Linux host
# with systemd. Works across Debian/Ubuntu LXCs, Proxmox host (PVE), and
# Ubuntu VPS targets. For postmarketOS / OpenRC use a separate script.
#
# Idempotent: re-running upgrades the binary in place and refreshes the
# unit + env file.
#
# Required env vars (read from /tmp/beszel-agent.env if present, or from
# the calling environment):
#   KEY         - hub public SSH key, e.g. "ssh-ed25519 AAAA..."
#   TOKEN       - per-system token (UUID), copied from "Add System" in hub UI
#   HUB_URL     - full hub URL incl. subpath, e.g. https://hub.example/beszel
#
# Optional:
#   LISTEN      - port or host:port (default: 45876)
#   BESZEL_TARBALL - path to pre-staged tarball
#                    (default: /tmp/beszel-agent_linux_amd64_glibc.tar.gz,
#                     fallback /tmp/beszel-agent_linux_amd64.tar.gz)
#   BESZEL_BIN_NAME  - bin name inside tarball (default: beszel-agent)
#
# After install:
#   - listens on :45876 by default (LAN-wide, gated by host firewall)
#   - data lives in /var/lib/beszel-agent
#   - service: `systemctl status beszel-agent`

set -euo pipefail

ENV_FILE_STAGING="/tmp/beszel-agent.env"
if [[ -f "${ENV_FILE_STAGING}" ]]; then
    # shellcheck disable=SC1090
    source "${ENV_FILE_STAGING}"
fi

: "${KEY:?KEY (hub public SSH key) is required}"
: "${TOKEN:?TOKEN is required}"
: "${HUB_URL:?HUB_URL is required}"
LISTEN="${LISTEN:-45876}"

# Tarball location: prefer glibc build on Debian/Ubuntu, fall back to
# the static (pure-Go) build for musl systems. Operator can override.
DEFAULT_GLIBC="/tmp/beszel-agent_linux_amd64_glibc.tar.gz"
DEFAULT_STATIC="/tmp/beszel-agent_linux_amd64.tar.gz"
if [[ -n "${BESZEL_TARBALL:-}" ]]; then
    TARBALL="${BESZEL_TARBALL}"
elif [[ -f "${DEFAULT_GLIBC}" ]]; then
    TARBALL="${DEFAULT_GLIBC}"
elif [[ -f "${DEFAULT_STATIC}" ]]; then
    TARBALL="${DEFAULT_STATIC}"
else
    echo "[beszel-agent-install] no tarball found in /tmp; aborting" >&2
    echo "  expected one of: ${DEFAULT_GLIBC} or ${DEFAULT_STATIC}" >&2
    exit 1
fi
BIN_NAME="${BESZEL_BIN_NAME:-beszel-agent}"

INSTALL_DIR="/opt/beszel-agent"
DATA_DIR="/var/lib/beszel-agent"
BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
SERVICE_PATH="/etc/systemd/system/beszel-agent.service"
ENV_FILE="/etc/default/beszel-agent"

echo "[beszel-agent-install] starting"
echo "[beszel-agent-install] HUB_URL=${HUB_URL}"
echo "[beszel-agent-install] LISTEN=${LISTEN}"
echo "[beszel-agent-install] tarball=${TARBALL}"

apt-get update -qq
apt-get install -y -qq tar ca-certificates iproute2

if ! id beszel-agent >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin beszel-agent
    echo "[beszel-agent-install] created system user 'beszel-agent'"
fi

# Add to 'disk' group so smartctl can read /dev/sd* on hosts with physical
# block devices. Harmless on LXCs / VMs that don't expose any.
if getent group disk >/dev/null 2>&1; then
    usermod -aG disk beszel-agent
fi
# Add to 'docker' group so the agent can read /var/run/docker.sock and
# expose container metrics. Harmless on hosts without docker.
if getent group docker >/dev/null 2>&1; then
    usermod -aG docker beszel-agent
fi

install -d -m 750 -o beszel-agent -g beszel-agent "${INSTALL_DIR}"
install -d -m 750 -o beszel-agent -g beszel-agent "${DATA_DIR}"

TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT
tar -xzf "${TARBALL}" -C "${TMPDIR}" "${BIN_NAME}"
install -m 755 -o beszel-agent -g beszel-agent "${TMPDIR}/${BIN_NAME}" "${BIN_PATH}"
echo "[beszel-agent-install] installed binary at ${BIN_PATH}"

umask 027
cat > "${ENV_FILE}" <<EOF
# Managed by beszel-agent-install.sh. Holds the per-system TOKEN secret.
KEY="${KEY}"
TOKEN=${TOKEN}
HUB_URL=${HUB_URL}
LISTEN=${LISTEN}
EOF
chown root:beszel-agent "${ENV_FILE}"
chmod 0640 "${ENV_FILE}"

cat > "${SERVICE_PATH}" <<EOF
[Unit]
Description=Beszel Agent
After=network.target

[Service]
Type=simple
User=beszel-agent
Group=beszel-agent
WorkingDirectory=${DATA_DIR}
EnvironmentFile=${ENV_FILE}
ExecStart=${BIN_PATH}
Restart=always
RestartSec=5
LimitNOFILE=4096

# light hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${DATA_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now beszel-agent
systemctl restart beszel-agent

# Wait for the agent to come up. In Beszel 0.18+ the agent has two modes:
#   - WS mode: the agent connects out to HUB_URL via WebSocket and the
#     hub talks back over the same tunnel. The agent does NOT open a
#     listening socket on $LISTEN. Look for "WebSocket connected" in logs.
#   - SSH mode (fallback / local hub): the agent opens an SSH server on
#     $LISTEN; the hub pulls metrics by connecting to it. Look for the
#     listening socket and "Starting SSH server" in logs.
LISTEN_PORT="${LISTEN##*:}"
for i in $(seq 1 20); do
    if journalctl -u beszel-agent --no-pager -n 50 2>/dev/null \
        | grep -qE 'WebSocket connected'; then
        echo "[beszel-agent-install] beszel-agent connected via WebSocket (after ${i}s)"
        rm -f "${ENV_FILE_STAGING}"
        exit 0
    fi
    if ss -ltn 2>/dev/null | grep -q ":${LISTEN_PORT} "; then
        echo "[beszel-agent-install] beszel-agent listening on :${LISTEN_PORT} (SSH mode, after ${i}s)"
        rm -f "${ENV_FILE_STAGING}"
        exit 0
    fi
    sleep 1
done

echo "[beszel-agent-install] ERROR: agent neither WS-connected nor listening on :${LISTEN_PORT}" >&2
systemctl --no-pager --full status beszel-agent >&2 || true
journalctl -u beszel-agent --no-pager -n 50 >&2 || true
exit 1
