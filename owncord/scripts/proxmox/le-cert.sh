#!/usr/bin/env bash
# Issue Let's Encrypt cert for owncord-pundef.mooo.com on nextcloud-vm (101).
# Prerequisite: public DNS A record owncord-pundef.mooo.com -> WAN IP (FreeDNS).
# Run on Proxmox host after: upload owncord/apache/owncord-pundef.conf + apply-vm-file.sh to /tmp/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=qm-guest.sh
source "${SCRIPT_DIR}/qm-guest.sh"

VMID=101
DOMAIN=owncord-pundef.mooo.com
CONF_LOCAL=/tmp/owncord-pundef.conf

echo "[owncord-le] checking public DNS for ${DOMAIN}..."
if ! qm_guest_rc "${VMID}" --timeout 30 -- getent hosts "${DOMAIN}" 2>/dev/null | grep -q .; then
  echo "[owncord-le] WARN: ${DOMAIN} not in public DNS yet. Add FreeDNS A record first." >&2
fi

echo "[owncord-le] certbot webroot..."
if ! qm_guest_rc "${VMID}" --timeout 300 -- bash -lc "
  set -e
  certbot certonly --webroot -w /var/www/html -d '${DOMAIN}' \
    --non-interactive --agree-tos --register-unsafely-without-email \
    --keep-until-expiring
  test -f /etc/letsencrypt/live/${DOMAIN}/fullchain.pem
  echo cert_ok
"; then
  echo "[owncord-le] FAILED: certbot or missing cert. Fix DNS/network, retry." >&2
  exit 1
fi

if [[ ! -f "${CONF_LOCAL}" ]]; then
  echo "[owncord-le] missing ${CONF_LOCAL} on Proxmox host — upload owncord/apache/owncord-pundef.conf first" >&2
  exit 1
fi

/tmp/apply-vm-file.sh "${VMID}" "${CONF_LOCAL}" /etc/apache2/sites-available/owncord-pundef.conf

qm_guest_rc "${VMID}" --timeout 60 -- bash -lc "
  set -e
  a2enmod -q proxy proxy_http proxy_wstunnel rewrite headers ssl 2>/dev/null || true
  a2ensite -q owncord-pundef.conf
  apache2ctl configtest
  systemctl reload apache2
  echo Apache using LE for ${DOMAIN}
"

echo "[owncord-le] done. Verify: curl -fsS https://${DOMAIN}/api/health"
