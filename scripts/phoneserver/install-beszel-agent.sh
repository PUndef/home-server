#!/usr/bin/env bash
# WSL/Linux orchestrator for Beszel agent on phoneserver.
# Usage: ./install-beszel-agent.sh <TOKEN>
#   PHONE_IP=192.168.1.116 ./install-beszel-agent.sh <TOKEN>

set -euo pipefail

TOKEN="${1:-${BESZEL_PHONESERVER_TOKEN:-}}"
PHONE_IP="${PHONE_IP:-192.168.1.116}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/phoneserver_nopass}"
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
REMOTE="pmos@${PHONE_IP}"
TAR="/tmp/beszel-agent_linux_arm64.tar.gz"
TAR_URL="https://github.com/henrygd/beszel/releases/download/${BESZEL_VERSION}/beszel-agent_linux_arm64.tar.gz"

echo "=== phoneserver Beszel agent (${PHONE_IP}) ==="
"${SSH[@]}" "${REMOTE}" "curl -fsS -m 8 -o /dev/null -w 'hub_http=%{http_code}\n' '${HUB_URL}/' || echo hub_unreachable"

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

"${SCP[@]}" "${TAR}" "${REPO_ROOT}/scripts/phoneserver/beszel-agent-install.sh" \
    "${REPO_ROOT}/scripts/phoneserver/beszel-battery-status-fix.sh" "${ENV_FILE}" "${REMOTE}:/tmp/"
"${SSH[@]}" "${REMOTE}" "mv /tmp/beszel-agent-phoneserver.env /tmp/beszel-agent.env; chmod 755 /tmp/beszel-agent-install.sh; chmod 600 /tmp/beszel-agent.env; sudo /tmp/beszel-agent-install.sh"
rm -f "${ENV_FILE}"

echo "done - check Beszel UI for phoneserver online"
