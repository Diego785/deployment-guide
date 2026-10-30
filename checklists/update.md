# Update

Details in [11 · Updates and rollback](../docs/11-updates-and-rollback.md).

- [ ] New image published with a version tag; CI green
- [ ] I know what changed, especially database migrations
- [ ] Current tag written down (`grep APP_TAG .env`)
- [ ] Database backup taken and not empty (`ls -lh backups/`)
- [ ] Tag changed in `.env`
- [ ] `docker compose pull app && docker compose up -d app`
- [ ] Logs clean, health OK, login OK, the new feature works
- [ ] If not: previous tag back, `up -d app`; restore the backup only if the migration requires it
