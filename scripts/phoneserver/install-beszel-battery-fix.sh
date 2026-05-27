#!/usr/bin/env bash
# Install sysfs status workaround for Beszel battery on phoneserver.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SSH=(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}")
SCP=(scp -o StrictHostKeyChecking=no -i "${SSH_KEY}")
REMOTE="pmos@${PHONE_IP}"

"${SCP[@]}" "${REPO_ROOT}/scripts/phoneserver/beszel-battery-status-fix.sh" "${REMOTE}:/tmp/"
"${SSH[@]}" "${REMOTE}" 'sudo mkdir -p /usr/local/sbin
sudo install -m 755 /tmp/beszel-battery-status-fix.sh /usr/local/sbin/beszel-battery-status-fix.sh

# Patch OpenRC init: run fix in start_pre before agent starts
INIT=/etc/init.d/beszel-agent
if ! grep -q beszel-battery-status-fix "${INIT}"; then
  sudo sed -i "/start_pre() {/a\\
    /usr/local/sbin/beszel-battery-status-fix.sh" "${INIT}"
fi

sudo /usr/local/sbin/beszel-battery-status-fix.sh
sudo rc-service beszel-agent restart
sleep 3
echo "=== status after fix ==="
cat /sys/class/power_supply/qcom_qg/status
sudo tail -5 /var/log/beszel-agent.log'

echo "done - refresh Beszel UI for battery %"
