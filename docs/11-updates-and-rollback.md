# 11 · Updates and rollback

## Use version tags, not `latest`

If compose says `image: my-app:latest`, you can't know what's running nor go back to "the one
before". Use an immutable tag (`1.4.0`, `sha-1a2b3c4`) and change it on each deploy.

A practical way: the tag in `.env`, the compose file never changes.

```yaml
    image: ghcr.io/me/my-app:${APP_TAG}
```

```bash
# .env
APP_TAG=1.4.0
```

## Updating

```bash
cd /srv/apps/my-app
docker compose exec db pg_dump -U my_app -Fc my_app > backups/before-1.5.0.dump   # 1. backup
sed -i 's/^APP_TAG=.*/APP_TAG=1.5.0/' .env                                       # 2. new tag
docker compose pull app                                                          # 3. download
docker compose up -d app                                                         # 4. replace
docker compose logs -f app                                                       # 5. watch
```

- Write down the previous tag before changing it (`grep APP_TAG .env`).
- Step 4 recreates only the app; the database keeps running.
- There's a short downtime (seconds) while the container restarts. Fine for most business apps;
  zero-downtime needs two app instances behind the proxy and is a topic of its own.
- Check: the health endpoint, a login, the feature you just shipped.

## Rolling back

```bash
sed -i 's/^APP_TAG=.*/APP_TAG=1.4.0/' .env
docker compose up -d app
```

**The catch: migrations.** If 1.5.0 changed the database (added a column, renamed a table), 1.4.0
may not work with it. Options, from best to worst:

1. **Backward-compatible migrations**: add things in one version, remove the old ones in a later
   version. Then the previous version still works with the new schema. Design for this.
2. **Restore the backup taken before updating** ([12](12-backups.md)). You lose what was written
   since the update.
3. A hand-written reverse migration. Risky under pressure.

That's why step 1 of every update is a backup.

## Rolling back nginx changes

Before editing a `.conf`, keep a copy **outside** `conf/` (nginx loads every `*.conf` in that
folder, and a copy inside would be loaded too, duplicating your `server`):

```bash
cp conf/app.example.com.conf ~/app.example.com.conf.bak
# … edit, test …
# if something went wrong:
cp ~/app.example.com.conf.bak conf/app.example.com.conf
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

## Changing only environment variables

```bash
nano .env
docker compose up -d app      # recreates the container with the new values
```

`docker compose restart` **does not** re-read `.env`; `up -d` does.

## Updating the database engine

A Postgres **minor** update (`16.3` → `16.4`) is just a new image: back up, `pull`, `up -d db`.
A **major** update (`16` → `17`) can't reuse the data folder: dump, start a new volume with the new
version, restore. Plan it; never change the major version tag casually.
