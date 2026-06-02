#!/usr/bin/env bash
# Restore owncord vhost to self-signed cert paths on VM 101.
set -euo pipefail
VMID=101
qm guest exec "${VMID}" --timeout 60 -- bash -lc '
  set -e
  sed -i "s|/etc/letsencrypt/live/owncord-pundef.mooo.com/|/etc/apache2/owncord-selfsigned/|g" /etc/apache2/sites-available/owncord-pundef.conf
  sed -i "/options-ssl-apache.conf/d" /etc/apache2/sites-available/owncord-pundef.conf
  apache2ctl configtest
  systemctl reload apache2
  echo restored_selfsigned
'
