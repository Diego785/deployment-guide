# 10 · Deploy step by step

The whole procedure for a new project on a server that already has a shared nginx. No proxy yet?
[16](16-server-from-scratch.md) and [17](17-shared-proxy-from-scratch.md) first. A system nginx, a
panel or another proxy? [18](18-servers-set-up-differently.md). Each step says
**what to do**, **how to check it** and **how to undo it**. Don't go to the next step until the
check passes.

Example values (replace them): project `my-app`, domain `app.example.com`, server
`203.0.113.10`, projects folder `/srv/apps`, proxy folder `/srv/nginx-proxy`, shared network
`proxy-network`, nginx container `nginx`. **Use the real ones from your inventory.**

## 0 · Before the server

- [ ] The app passes [03 · Preparing the app](03-preparing-the-app.md) and runs locally with the
  same `docker-compose.yml`.
- [ ] The image is in a registry (or you know you'll build on the server) — [05](05-image-and-registry.md).
- [ ] You have the inventory and its answers — [02](02-inventory.md).
- [ ] You've chosen names nobody uses: folder, `container_name`s, compose `name`, domain.

## 1 · Create the project folder

```bash
mkdir -p /srv/apps/my-app/backups
cd /srv/apps/my-app
```

- **Check:** `pwd` shows the folder; `ls` is empty except `backups`.
- **Undo:** `rmdir /srv/apps/my-app/backups /srv/apps/my-app` (only removes empty folders).

## 2 · Write the compose file and the `.env`

Copy [templates/docker-compose.yml](../templates/docker-compose.yml) and
[templates/.env.example](../templates/.env.example), adapt them, and on the server:

```bash
nano docker-compose.yml      # paste, save (Ctrl+O, Enter), exit (Ctrl+X)
nano .env                    # paste and fill in real values
chmod 600 .env
openssl rand -hex 24         # use this kind of output for passwords and secrets
```

- **Check:** `docker compose config` prints the YAML with no errors and with the values filled in.
  Make sure the network name under `external: true` matches the real shared network.
- **Undo:** delete the two files.

## 3 · Get the image

```bash
docker login ghcr.io -u <user>     # only if it's private and the server isn't logged in yet
docker compose pull
```

- **Check:** `docker images | grep my-app` lists it.
- **Undo:** `docker image rm <image>:<tag>` (only your image).

## 4 · Start the database first

```bash
docker compose up -d db
docker compose ps
```

- **Check:** `db` shows `healthy` after a few seconds. `docker compose logs db` ends with
  `database system is ready to accept connections`.
- **Undo:** `docker compose down` (keeps the volume; add `-v` only to delete an empty database you
  just created).

## 5 · Start the app

```bash
docker compose up -d
docker compose ps
docker compose logs -f app       # Ctrl+C to stop watching
```

- **Check:** `app` is `Up` (or `healthy`), doesn't keep restarting, and the logs show migrations
  done and the server listening. From the server, test it inside the network:

  ```bash
  docker exec nginx curl -s http://my-app:3000/api/health
  ```

  It must answer (e.g. `{"status":"ok"}`). If `nginx` can't resolve `my-app`, the app isn't on the
  shared network: check `networks:` in compose.
- **Undo:** `docker compose down`.

## 6 · Look at it without a domain

SSH tunnel, from your computer ([09](09-without-a-domain.md)). Create the first user, click around,
check it's what you expected.

## 7 · nginx phase 1 (HTTP)

```bash
cd /srv/nginx-proxy
ls conf/                                  # see the existing files and their naming
nano conf/app.example.com.conf            # paste templates/nginx/phase1-http.conf, adapted
docker exec nginx nginx -t
```

- **Check:** `nginx -t` says `syntax is ok` and `test is successful`. **Only then:**

  ```bash
  docker exec nginx nginx -s reload
  curl -I -H "Host: app.example.com" http://127.0.0.1/
  ```

  The `curl` must show your app's answer (`200`, or a `30x` to your login), not another site's.
- **Undo:** `rm conf/app.example.com.conf && docker exec nginx nginx -t && docker exec nginx nginx -s reload`.

You can test from your computer with a `hosts` entry ([09](09-without-a-domain.md), option 2).

## 8 · DNS

Create (or ask for) the A record `app.example.com → 203.0.113.10` ([08](08-dns.md)).

- **Check:** `nslookup app.example.com 1.1.1.1` returns the server's IP. Then
  `curl -I http://app.example.com` from your computer reaches your app.
- **Undo:** delete the record.

## 9 · Certificate

From the proxy folder, dry run and then the real one ([07](07-https-certbot.md)):

```bash
docker compose run --rm certbot certonly --webroot -w /var/www/certbot -d app.example.com --dry-run
docker compose run --rm certbot certonly --webroot -w /var/www/certbot -d app.example.com \
  --email you@example.com --agree-tos --no-eff-email
```

- **Check:** "Successfully received certificate" and the path
  `/etc/letsencrypt/live/app.example.com/`.
- **Undo:** `docker compose run --rm certbot delete --cert-name app.example.com`.

## 10 · nginx phase 2 (HTTPS)

```bash
cp conf/app.example.com.conf ~/app.example.com.conf.phase1     # keep phase 1 to go back
nano conf/app.example.com.conf                                 # replace with phase 2
docker exec nginx nginx -t && docker exec nginx nginx -s reload
```

- **Check:** `https://app.example.com` opens with the padlock; `http://` redirects to `https://`;
  logging in works (cookies, redirects use the right URL).
- **Undo:** `cp ~/app.example.com.conf.phase1 conf/app.example.com.conf`, test, reload.

## 11 · Leave it in a good state

- [ ] `APP_URL` in `.env` is `https://app.example.com` (restart the app if you changed it).
- [ ] Backups scheduled and **one restore tested** ([12](12-backups.md)).
- [ ] Certificate renewal exists on the server ([07](07-https-certbot.md)).
- [ ] No temporary `ports:` left in compose; `docker ps` shows no published ports for your project.
- [ ] Temporary files and phase 1 copy removed (`~/app.example.com.conf.phase1`).
- [ ] A short note (in your project's repo, not on the server) with: folder, containers, domain,
  how to update, how to back up, where the `.env` is.
- [ ] If the server isn't yours: tell the admin what you added (folder, `.conf`, domain).
