#!/bin/bash
set -euo pipefail

NC_PATH="/var/www/nextcloud"
BACKUP_ROOT="/backup/nextcloud"
MYSQL_CNF="/root/.nextcloud-mysql-backup.cnf"
DATE="$(date +%Y%m%d_%H%M%S)"

APP_BKP="${BACKUP_ROOT}/app_${DATE}.tar.gz"
DATA_BKP="${BACKUP_ROOT}/data_${DATE}.tar.gz"
SQL_BKP="${BACKUP_ROOT}/nextcloud-sqlbkp_${DATE}.bak.gz"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

maintenance_off() {
  sudo -u www-data php "$NC_PATH/occ" maintenance:mode --off >/dev/null 2>&1 || true
}

purge_old_backups() {
  find "$BACKUP_ROOT" -maxdepth 1 -type f \( \
    -name 'app_*.tar.gz' -o \
    -name 'data_*.tar.gz' -o \
    -name 'nextcloud-sqlbkp_*.bak.gz' \
  \) -delete
}

trap 'log "ERROR: backup failed (line $LINENO). Turning maintenance mode off."; maintenance_off' ERR

log "=== Nextcloud backup start ==="

mkdir -p "$BACKUP_ROOT"

log "Removing previous backups (keep one set only)..."
purge_old_backups
log "Old backups removed."

log "Enabling maintenance mode..."
sudo -u www-data php "$NC_PATH/occ" maintenance:mode --on
log "Maintenance on."

log "Backing up app (tar.gz)..."
tar czf "$APP_BKP" -C /var/www nextcloud
log "App backup done: $(du -h "$APP_BKP" | cut -f1)"

log "Backing up data (tar.gz)..."
tar czf "$DATA_BKP" -C /var/www nextcloud-data
log "Data backup done: $(du -h "$DATA_BKP" | cut -f1)"

log "Dumping database (gzip)..."
mysqldump --defaults-extra-file="$MYSQL_CNF" --single-transaction --default-character-set=utf8mb4 nextcloud | gzip > "$SQL_BKP"
log "Database dump done: $(du -h "$SQL_BKP" | cut -f1)"

log "Disabling maintenance mode..."
sudo -u www-data php "$NC_PATH/occ" maintenance:mode --off
log "Maintenance off."

log "=== Nextcloud backup finished ==="
