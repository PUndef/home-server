#!/usr/bin/env bash
# WSL/Linux orchestrator for Beszel agent on phoneserver (v25.12 / systemd).
# Usage: ./install-beszel-agent.sh <TOKEN>
#   PHONE_IP=192.168.50.127 ./install-beszel-agent.sh <TOKEN>

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"

TOKEN="${1:-${BESZEL_PHONESERVER_TOKEN:-}}"
HUB_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH9I03DG8DciIm5AklgrMF1GMQoIlYibQxKWbzzdFv3W'
HUB_URL="${HUB_URL:-http://192.168.50.35/beszel}"
BESZEL_VERSION="${BESZEL_VERSION:-v0.18.7}"
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [[ -z "${TOKEN}" ]]; then
    echo "usage: $0 <TOKEN>" >&2
    exit 2
fi
if [[ ! -f "${SSH_KEY}" ]]; then
    echo "missing SSH key: ${SSH_KEY}" >&2
    exit 1
fi

SSH=(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}")
SCP=(scp -o StrictHostKeyChecking=no -i "${SSH_KEY}")
TAR="/tmp/beszel-agent_linux_arm64.tar.gz"
TAR_URL="https://github.com/henrygd/beszel/releases/download/${BESZEL_VERSION}/beszel-agent_linux_arm64.tar.gz"

echo "=== phoneserver Beszel agent (${SSH_REMOTE}) ==="
"${SSH[@]}" "${SSH_REMOTE}" "curl -fsS -m 8 -o /dev/null -w 'hub_http=%{http_code}\n' '${HUB_URL}/' || echo hub_unreachable"

if [[ ! -f "${TAR}" ]]; then
    echo "downloading ${TAR_URL}"
    curl -fsSL -o "${TAR}" "${TAR_URL}"
fi
echo "tarball: $(wc -c < "${TAR}") bytes"

ENV_FILE="/tmp/beszel-agent-phoneserver.env"
cat > "${ENV_FILE}" <<EOF
KEY="${HUB_KEY}"
TOKEN=${TOKEN}
HUB_URL=${HUB_URL}
LISTEN=45876
EOF
chmod 600 "${ENV_FILE}"

"${SCP[@]}" "${TAR}" \
    "${REPO_ROOT}/scripts/phoneserver/beszel-agent-install-systemd.sh" \
    "${REPO_ROOT}/scripts/phoneserver/beszel-battery-status-fix.sh" \
    "${ENV_FILE}" "${SSH_REMOTE}:/tmp/"
"${SSH[@]}" "${SSH_REMOTE}" \
    "mv /tmp/beszel-agent-phoneserver.env /tmp/beszel-agent.env; \
     chmod 755 /tmp/beszel-agent-install-systemd.sh; chmod 600 /tmp/beszel-agent.env; \
     sudo /tmp/beszel-agent-install-systemd.sh"
rm -f "${ENV_FILE}"

echo "done - check Beszel UI for phoneserver online"
