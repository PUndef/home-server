#!/usr/bin/env bash
# Apache HTTPS edge for OwnCord on nextcloud-vm (101).
# Run on Proxmox host after uploading owncord/apache/owncord-pundef.conf to /tmp/owncord-pundef.conf
set -euo pipefail

VMID=101
CONF_LOCAL=/tmp/owncord-pundef.conf
DOMAIN=owncord-pundef.mooo.com
LE_CERT=/etc/letsencrypt/live/${DOMAIN}/fullchain.pem
CERT_DIR=/etc/apache2/owncord-selfsigned

apply() {
  /tmp/apply-vm-file.sh "$@"
}

# Self-signed fallback only if LE cert is not issued yet.
qm guest exec "${VMID}" --timeout 60 -- bash -lc "
  set -e
  if [[ -f '${LE_CERT}' ]]; then
    echo 'LE cert exists, skip self-signed'
    exit 0
  fi
  CERT_DIR=/etc/apache2/owncord-selfsigned
  mkdir -p \"\${CERT_DIR}\"
  if [[ ! -f \"\${CERT_DIR}/fullchain.pem\" ]]; then
    openssl req -x509 -nodes -days 825 -newkey rsa:2048 \
      -keyout \"\${CERT_DIR}/privkey.pem\" \
      -out \"\${CERT_DIR}/fullchain.pem\" \
      -subj '/CN=${DOMAIN}/O=pundef-homelab'
    chmod 600 \"\${CERT_DIR}/privkey.pem\"
    echo 'created self-signed cert (run owncord/scripts/proxmox/le-cert.sh after FreeDNS)'
  fi
"

apply "${VMID}" "${CONF_LOCAL}" /etc/apache2/sites-available/owncord-pundef.conf

# If LE not issued yet, point vhost at self-signed paths so Apache starts.
qm guest exec "${VMID}" --timeout 60 -- bash -lc "
  set -e
  if [[ ! -f '${LE_CERT}' ]]; then
    sed -i 's|/etc/letsencrypt/live/${DOMAIN}/|${CERT_DIR}/|g' /etc/apache2/sites-available/owncord-pundef.conf
    sed -i '/options-ssl-apache.conf/d' /etc/apache2/sites-available/owncord-pundef.conf
  fi
  a2enmod -q proxy proxy_http proxy_wstunnel rewrite headers ssl 2>/dev/null || true
  a2ensite -q owncord-pundef.conf
  a2dissite -q spacebar-pundef.conf chat-pundef.conf voice-pundef.conf revolt-pundef.conf 2>/dev/null || true
  apache2ctl configtest
  systemctl reload apache2
  echo 'Apache reloaded for ${DOMAIN}'
"
