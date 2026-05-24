#!/usr/bin/env bash
# beszel-agent-install-vps.sh
#
# VPS wrapper around scripts/proxmox/beszel-agent-install.sh.
# Downloads the agent tarball from GitHub on the VPS itself (public internet),
# then delegates to the shared installer.
#
# Requires /tmp/beszel-agent.env with KEY, TOKEN, HUB_URL (and optional LISTEN).
# Run as root, or via sudo.

set -euo pipefail

VERSION="${BESZEL_VERSION:-v0.18.7}"
TARBALL="/tmp/beszel-agent_linux_amd64_glibc.tar.gz"
INSTALLER="/tmp/beszel-agent-install.sh"

if [[ ! -f /tmp/beszel-agent.env ]]; then
    echo "[beszel-agent-install-vps] missing /tmp/beszel-agent.env" >&2
    exit 1
fi

if [[ ! -f "${INSTALLER}" ]]; then
    echo "[beszel-agent-install-vps] missing ${INSTALLER}" >&2
    exit 1
fi

if [[ ! -f "${TARBALL}" ]]; then
    echo "[beszel-agent-install-vps] downloading ${VERSION} tarball"
    curl -fsSL -o "${TARBALL}" \
        "https://github.com/henrygd/beszel/releases/download/${VERSION}/beszel-agent_linux_amd64_glibc.tar.gz"
fi

exec bash "${INSTALLER}"
