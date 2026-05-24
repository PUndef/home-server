#!/usr/bin/env bash
# Self-contained Beszel agent install for sweet-home-vps (Neth).
# Run on the VPS console as root, or: sudo bash install-beszel-neth-console.sh

set -euo pipefail

KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9I03DG8DciIm5AklgrMF1GMQoIlYibQxKWbzzdFv3W'
TOKEN="${BESZEL_NETH_TOKEN:?export BESZEL_NETH_TOKEN from Beszel UI (Add System sweet-home-vps)}"
HUB_URL='https://apps-pundef.mooo.com/beszel'
LISTEN='45876'
VERSION='v0.18.7'
TARBALL='/tmp/beszel-agent_linux_amd64_glibc.tar.gz'

echo "[neth-beszel] installing agent ${VERSION}"

apt-get update -qq
apt-get install -y -qq curl tar ca-certificates

if [[ ! -f "${TARBALL}" ]]; then
  curl -fsSL -o "${TARBALL}" \
    "https://github.com/henrygd/beszel/releases/download/${VERSION}/beszel-agent_linux_amd64_glibc.tar.gz"
fi

if ! id beszel-agent >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin beszel-agent
fi

install -d -m 750 -o beszel-agent -g beszel-agent /opt/beszel-agent /var/lib/beszel-agent
TMPDIR="$(mktemp -d)"
trap 'rm -rf "${TMPDIR}"' EXIT
tar -xzf "${TARBALL}" -C "${TMPDIR}" beszel-agent
install -m 755 -o beszel-agent -g beszel-agent "${TMPDIR}/beszel-agent" /opt/beszel-agent/beszel-agent

umask 027
cat > /etc/default/beszel-agent <<EOF
KEY="${KEY}"
TOKEN=${TOKEN}
HUB_URL=${HUB_URL}
LISTEN=${LISTEN}
EOF
chown root:beszel-agent /etc/default/beszel-agent
chmod 640 /etc/default/beszel-agent

cat > /etc/systemd/system/beszel-agent.service <<EOF
[Unit]
Description=Beszel Agent
After=network.target

[Service]
Type=simple
User=beszel-agent
Group=beszel-agent
WorkingDirectory=/var/lib/beszel-agent
EnvironmentFile=/etc/default/beszel-agent
ExecStart=/opt/beszel-agent/beszel-agent
Restart=always
RestartSec=5
LimitNOFILE=4096
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=/var/lib/beszel-agent

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now beszel-agent

for i in $(seq 1 20); do
  if journalctl -u beszel-agent --no-pager -n 20 2>/dev/null | grep -q 'WebSocket connected'; then
    echo "[neth-beszel] WebSocket connected (after ${i}s)"
    exit 0
  fi
  sleep 1
done

echo "[neth-beszel] ERROR: agent did not connect" >&2
journalctl -u beszel-agent --no-pager -n 20 >&2
exit 1
