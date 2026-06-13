#!/usr/bin/env bash
# Install sysfs status workaround for Beszel battery on phoneserver (systemd).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=phone-defaults.sh
source "${SCRIPT_DIR}/phone-defaults.sh"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SSH=(ssh -o StrictHostKeyChecking=no -i "${SSH_KEY}")
SCP=(scp -o StrictHostKeyChecking=no -i "${SSH_KEY}")

"${SCP[@]}" "${REPO_ROOT}/scripts/phoneserver/beszel-battery-status-fix.sh" "${SSH_REMOTE}:/tmp/"
"${SSH[@]}" "${SSH_REMOTE}" 'sudo install -m 755 /tmp/beszel-battery-status-fix.sh /usr/local/sbin/beszel-battery-status-fix.sh
sudo /usr/local/sbin/beszel-battery-status-fix.sh
sudo systemctl restart beszel-agent
sleep 3
echo "=== status after fix ==="
cat /sys/class/power_supply/qcom_qg/status
sudo journalctl -u beszel-agent --no-pager -n 5'

echo "done - refresh Beszel UI for battery %"
