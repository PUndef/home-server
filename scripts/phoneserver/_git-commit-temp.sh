#!/bin/bash
set -e
cd /mnt/d/repositories/home-server
git add owncord-setup.md scripts/phoneserver/
git commit -m 'docs: OwnCord plan and phoneserver LCD status scripts' \
  -m 'OwnCord setup notes for homelab and phoneserver. Optional fbcon LCD status, term-status, wake-display, diag probes.'
git status
