#!/usr/bin/env bash
# Dumps a Postgres database running in a compose project, keeps the last N days and can copy the
# dump off the server. Run it from cron; it exits non-zero if anything fails.
#
# Settings (edit, or export before running):
#   PROJECT_DIR   folder with the docker-compose.yml
#   SERVICE       compose service of the database
#   DB_NAME, DB_USER
#   KEEP_DAYS     how many days of dumps to keep
#   OFFSITE_CMD   optional command that receives the dump path as $1, e.g.
#                 'rclone copy "$1" remote:my-app-backups'
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-/srv/apps/my-app}"
SERVICE="${SERVICE:-db}"
DB_NAME="${DB_NAME:-my_app}"
DB_USER="${DB_USER:-my_app}"
KEEP_DAYS="${KEEP_DAYS:-30}"
OFFSITE_CMD="${OFFSITE_CMD:-}"

BACKUP_DIR="$PROJECT_DIR/backups"
FILE="$BACKUP_DIR/${DB_NAME}-$(date +%F-%H%M).dump"

mkdir -p "$BACKUP_DIR"
cd "$PROJECT_DIR"

echo "$(date -Is) dumping $DB_NAME to $FILE"
docker compose exec -T "$SERVICE" pg_dump -U "$DB_USER" -Fc "$DB_NAME" > "$FILE.partial"

# A valid custom-format dump starts with "PGDMP"; anything else is an error message.
if [ "$(head -c 5 "$FILE.partial")" != "PGDMP" ]; then
  echo "$(date -Is) ERROR: the dump is not valid" >&2
  rm -f "$FILE.partial"
  exit 1
fi
mv "$FILE.partial" "$FILE"
chmod 600 "$FILE"
echo "$(date -Is) ok, $(du -h "$FILE" | cut -f1)"

if [ -n "$OFFSITE_CMD" ]; then
  echo "$(date -Is) copying off the server"
  bash -c "$OFFSITE_CMD" _ "$FILE"
fi

find "$BACKUP_DIR" -name "${DB_NAME}-*.dump" -type f -mtime +"$KEEP_DAYS" -print -delete
