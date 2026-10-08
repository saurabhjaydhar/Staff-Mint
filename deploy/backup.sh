#!/usr/bin/env bash
# Daily MongoDB backup (cron: 0 2 * * * /opt/staffmint/deploy/backup.sh). Keeps 14 days.
# Prefer Atlas continuous backup / point-in-time restore in production; this is the VPS fallback.
set -euo pipefail
DIR=${BACKUP_DIR:-/var/backups/staffmint}
mkdir -p "$DIR"
STAMP=$(date +%F-%H%M)
docker compose -f /opt/staffmint/docker-compose.yml exec -T mongo mongodump --archive --gzip > "$DIR/staffmint-$STAMP.archive.gz"
find "$DIR" -name 'staffmint-*.archive.gz' -mtime +14 -delete
echo "backup ok: $DIR/staffmint-$STAMP.archive.gz"
# Restore drill: docker compose exec -T mongo mongorestore --archive --gzip --drop < file.archive.gz
