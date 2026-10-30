# 12 · Backups

A backup you haven't restored is a hope, not a backup. Back up automatically, keep copies off the
server, and test a restore.

## Manual backup (Postgres)

```bash
cd /srv/apps/my-app
docker compose exec -T db pg_dump -U my_app -Fc my_app > backups/my_app-$(date +%F-%H%M).dump
ls -lh backups/
```

- `-Fc` is the "custom" format: compressed, and `pg_restore` can restore it selectively.
- `-T` avoids a TTY, so the binary output isn't corrupted.
- An empty or tiny file (a few bytes) means it failed: read the error.

MySQL/MariaDB equivalent:
`docker compose exec -T db mysqldump -u root -p"$MYSQL_ROOT_PASSWORD" my_db > backups/my_db.sql`.

## Automatic backups with rotation

[scripts/backup-postgres.sh](../scripts/backup-postgres.sh) makes a dump, deletes the ones older
than N days and can copy it elsewhere. Put it in the project folder and schedule it:

```bash
chmod +x /srv/apps/my-app/backup-postgres.sh
crontab -e
```

```cron
# Every day at 02:30
30 2 * * * /srv/apps/my-app/backup-postgres.sh >> /srv/apps/my-app/backups/backup.log 2>&1
```

Check the next day: `ls -lh /srv/apps/my-app/backups/` and `tail backups/backup.log`.

## Off the server

If the server dies or the disk is lost, backups inside it go with it. At least one of:

- **Pull from your computer** now and then: `scp my-server:/srv/apps/my-app/backups/*.dump .`
- **Push to object storage** (S3, Backblaze B2, Cloudflare R2) with `rclone` or `aws s3 cp`, with a
  key that can only write to that bucket.
- **A second server** with `rsync`.

The data is your client's: encrypt copies that leave the server (`gpg -c` or the storage's own
encryption) and don't keep them on personal laptops longer than needed.

## Restoring

Practise on a **copy**, never directly on production:

```bash
# 1. A throwaway database container
docker run -d --name restore-test -e POSTGRES_PASSWORD=test postgres:16-alpine
sleep 5
# 2. Load the dump
docker exec -i restore-test createdb -U postgres my_app
docker exec -i restore-test pg_restore -U postgres -d my_app --no-owner < backups/my_app-2026-01-31-0230.dump
# 3. Check something
docker exec -it restore-test psql -U postgres my_app -c "select count(*) from users;"
# 4. Remove it
docker rm -f restore-test
```

Restoring over the real database (emergency; the app stopped first):

```bash
docker compose stop app
docker compose exec -T db pg_restore -U my_app -d my_app --clean --if-exists --no-owner < backups/<file>.dump
docker compose start app
```

`--clean` drops objects before recreating them: everything written after that backup is lost.

## Files

Uploads in a volume are backed up by archiving the volume:

```bash
docker run --rm -v my-app_uploads:/data -v "$PWD/backups":/backup alpine \
  tar czf /backup/uploads-$(date +%F).tar.gz -C /data .
```
