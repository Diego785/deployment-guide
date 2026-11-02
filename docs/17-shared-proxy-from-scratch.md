# 17 · The shared proxy from scratch

How to set up the single nginx that every project on the server will share, on a server that has
none ([16](16-server-from-scratch.md) done, or the [inventory](02-inventory.md) says "Container
publishing 443: none found" **and** nothing else listens on 80/443). [06](06-nginx-proxy.md) explains
how the proxy works; this chapter builds it.

If something already listens on 80 or 443 (`sudo ss -tlnp | grep -E ':(80|443) '`), **stop**: there
is a web server or panel in place. Read [18](18-servers-set-up-differently.md) instead of adding a
second one; two programs can't share a port.

## 1 · Folders

```bash
cd /srv/nginx-proxy
mkdir -p conf certbot/www certbot/conf
```

- **Check:** `ls` shows `conf` and `certbot`.

## 2 · The compose file

Copy [templates/nginx-proxy/docker-compose.yml](../templates/nginx-proxy/docker-compose.yml) to
`/srv/nginx-proxy/docker-compose.yml`. What it does:

- `nginx` publishes **80 and 443**: the only published ports on the server.
- `conf/` is where each project drops its `.conf`; `certbot/www` holds the challenge files and
  `certbot/conf` the certificates. nginx mounts the last two read-only.
- `certbot` has `profiles: ["tools"]`: it never runs by itself, only when you call
  `docker compose run --rm certbot …`.
- The network `proxy-network` is **external**: created once by hand
  ([16, step 11](16-server-from-scratch.md#11--folders-and-the-shared-network)) so that no single project
  owns it and `docker compose down` here never deletes it.

```bash
docker network ls | grep proxy-network || docker network create proxy-network
docker compose config -q && echo ok
```

- **Check:** `ok`.

## 3 · The default site

Copy [templates/nginx/00-default.conf](../templates/nginx/00-default.conf) to `conf/00-default.conf`.

Without it, a request for the bare IP or for a domain that isn't configured gets the **first site
nginx loaded**, alphabetically: visitors see a client's app under the wrong name, and search engines
index it. The default site closes those connections instead.

## 4 · Start nginx

```bash
docker compose up -d nginx
docker compose ps
docker exec nginx nginx -t
```

- **Check:** `nginx` is `Up`; `nginx -t` says `syntax is ok` and `test is successful`. From your
  computer:

  ```bash
  curl -I http://203.0.113.10        # "Empty reply from server": the default site closed it
  ```

  If it times out instead, port 80 is blocked by ufw or the provider's firewall
  ([16, step 6](16-server-from-scratch.md#6--firewall-ufw)).
- **Undo:** `docker compose down` (no project depends on it yet).

## 5 · Test the challenge path

Before the first certificate, prove that Let's Encrypt will be able to fetch files. Use a domain
that already points to the server ([08](08-dns.md)), or the IP:

```bash
mkdir -p certbot/www/.well-known/acme-challenge
echo ok > certbot/www/.well-known/acme-challenge/test
curl http://203.0.113.10/.well-known/acme-challenge/test       # from your computer: "ok"
rm certbot/www/.well-known/acme-challenge/test
```

- **Check:** prints `ok`.

## 6 · Automatic certificate renewal

You run this proxy, so renewal is your job. Set it up now, before the first certificate, so it's
never forgotten:

```bash
sudo crontab -e
```

```cron
# Every day at 03:17: renew certificates that are due, then reload nginx so it serves them
17 3 * * * { cd /srv/nginx-proxy && docker compose run --rm certbot renew --quiet && docker exec nginx nginx -s reload; } >> /var/log/certbot-renew.log 2>&1
```

- **Check:** `sudo crontab -l` shows the line. After the first certificate exists,
  `docker compose run --rm certbot renew --dry-run` must say the renewal would succeed.
- `renew` does nothing for certificates with more than 30 days left, so running it daily is safe.

## 7 · Your first site

Follow [10 · Deploy step by step](10-deploy-step-by-step.md) with these values:

- proxy folder `/srv/nginx-proxy`, nginx container `nginx`, network `proxy-network`;
- webroot inside nginx `/var/www/certbot`, certificates inside nginx
  `/etc/letsencrypt/live/<domain>/`.

## Updating the proxy

nginx itself needs updates now and then (security fixes). Because every site depends on it, do it
deliberately:

```bash
cd /srv/nginx-proxy
nano docker-compose.yml               # e.g. nginx:1.27-alpine → nginx:1.28-alpine
docker compose pull nginx
docker run --rm -v "$PWD/conf:/etc/nginx/conf.d:ro" -v "$PWD/certbot/conf:/etc/letsencrypt:ro" \
  --network proxy-network nginx:1.28-alpine nginx -t      # test the new version with today's files
docker compose up -d nginx            # a few seconds without service for every site
docker exec nginx nginx -t && docker compose ps
```

- **Check:** the test with the new version passes **before** `up -d`; after it, every site opens.
- **Undo:** put the previous tag back in the file and `docker compose up -d nginx`.
- On a server with several clients, announce the minute of downtime.

## What goes in each project, and what doesn't

| In the proxy folder | In each project's folder |
| --- | --- |
| `docker-compose.yml` of nginx + certbot | The app's `docker-compose.yml` and `.env` |
| `conf/<domain>.conf`, one per site | Nothing about nginx |
| Certificates for every domain | Backups of its own database |
| The renewal cron | Its own backup cron |

A project never publishes ports and never runs its own nginx on 80/443: it joins `proxy-network`
and adds one `.conf`.
