# 19 · Advanced: moving, automating, watching

Once a project runs well: moving it to another server, deploying from CI, knowing when it breaks
before the client tells you, and the less common certificate and proxy cases.

## Moving a project to another server

The plan in one line: **set up the new server, copy the data, switch DNS, keep the old one for a
while**. Example: `old` = `203.0.113.10`, `new` = `198.51.100.20`.

**The day before**

1. Lower the DNS record's **TTL to 300** (5 minutes) in the DNS panel. Wait for the old TTL to pass
   (often 1 hour or 1 day): after that, the switch spreads in minutes.
2. Prepare `new`: [16](16-server-from-scratch.md) and [17](17-shared-proxy-from-scratch.md) (or
   follow its conventions if it's already set up).
3. Deploy the project on `new` exactly as on `old`: same compose, same `.env` (copy it by `scp`
   between servers or retype it; never through a chat), same image tag. Start only the database:
   `docker compose up -d db`.

**The switch** (announce a few minutes without service)

```bash
# On old: stop writes, so nothing changes after the dump
cd /srv/apps/my-app && docker compose stop app
docker compose exec -T db pg_dump -U my_app -Fc my_app > backups/move.dump
# From old to new (or via your computer)
scp backups/move.dump deploy@198.51.100.20:/srv/apps/my-app/backups/
# On new: load it and start the app
cd /srv/apps/my-app
docker compose exec -T db pg_restore -U my_app -d my_app --clean --if-exists --no-owner < backups/move.dump
docker compose up -d
```

- **Files** the app stores (uploads in a volume): copy the volume too, e.g.
  `docker run --rm -v my-app_uploads:/data -v "$PWD":/out alpine tar czf /out/uploads.tgz -C /data .`
  on `old`, then the reverse (`tar xzf`) on `new`.
- **The certificate:** Let's Encrypt validates over HTTP, so on `new` it only works **after** DNS
  points there. Two options:
  - Load phase 1 on `new`, switch DNS, request the certificate, load phase 2 (a few minutes of
    HTTP only).
  - Or copy the certificate folder from `old` (`certbot/conf/live/<domain>`, `archive/<domain>`,
    `renewal/<domain>.conf`, keeping the structure) and load phase 2 directly: no HTTP gap.

**Switch DNS**: change the A record to `198.51.100.20`. Check with
`nslookup app.example.com 1.1.1.1`, then log in and check the latest data is there.

**Afterwards**

- Keep `old` stopped (not deleted) for a week or two. If something's missing, it's still there.
- Raise the TTL again. Then retire the project on `old` ([13](13-retiring-a-project.md)).

**Undo** (if `new` fails during the switch): DNS back to `203.0.113.10`, and on `old`
`docker compose start app`. Nothing was deleted there.

## Deploying from CI (GitHub Actions)

Once manual deploys are routine, CI can run the same commands after publishing the image. Only do
it when the manual procedure has worked several times: automation repeats mistakes faster.

On the server, a deploy script in the project folder, so CI runs exactly what you run by hand:

```bash
nano /srv/apps/my-app/deploy.sh
```

```bash
#!/bin/sh
# Back up, then update the app to the image tag in .env. Run from the project folder.
set -eu
cd "$(dirname "$0")"
./backup.sh                          # your backup script (12)
docker compose pull app
docker compose up -d app
docker compose ps app
```

```bash
chmod +x /srv/apps/my-app/deploy.sh
/srv/apps/my-app/deploy.sh           # try it by hand first
```

A key **only for CI**, allowed to run that script and nothing else:

```bash
# On your computer: a new key without passphrase (CI can't type one)
ssh-keygen -t ed25519 -f ci-deploy -C "ci-deploy" -N ""
cat ci-deploy.pub                    # copy the line
```

On the server, add it to `~/.ssh/authorized_keys` of `deploy` with a forced command in front, on a
single line:

```text
command="/srv/apps/my-app/deploy.sh",no-port-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA… ci-deploy
```

Whatever CI asks for, this key only runs `deploy.sh`. Store `ci-deploy` (the private half) as a
repository secret (`DEPLOY_SSH_KEY`) plus `DEPLOY_HOST`, then delete both files from your computer.

```yaml
# .github/workflows/deploy.yml (after the image job; see 05)
  deploy:
    needs: image
    runs-on: ubuntu-latest
    environment: staging            # GitHub can require an approval per environment
    steps:
      - name: Deploy
        env:
          KEY: ${{ secrets.DEPLOY_SSH_KEY }}
          HOST: ${{ secrets.DEPLOY_HOST }}
        run: |
          install -m 600 /dev/null key && printf '%s\n' "$KEY" > key
          ssh -i key -o StrictHostKeyChecking=accept-new deploy@"$HOST" deploy
```

- If `.env` pins a version tag ([11](11-updates-and-rollback.md)), CI must change it first, or
  publish the tag the server already follows (e.g. `staging`). Pick one and write it down.
- **Check:** the job's log shows the compose output; `docker compose ps` on the server shows the
  new image.
- **Undo:** remove the key's line from `authorized_keys`; delete the secrets.

## Knowing when it breaks

- **An external uptime check** (UptimeRobot, Better Stack, Healthchecks.io, or your own Uptime Kuma
  on another server) calling `https://app.example.com/api/health` every few minutes, with an email
  or chat alert. It also tells you when the certificate is about to expire.
- **Healthchecks in compose** plus `restart: unless-stopped`: Docker restarts a crashed app; the
  uptime check tells you if it keeps crashing.
- **Disk and memory**: a daily cron that warns when the disk passes 85%:

  ```cron
  # crontab -e: every day at 08:00, print a warning only when / is over 85% full
  0 8 * * * used=$(df --output=pcent / | tail -1 | tr -dc 0-9); [ "$used" -gt 85 ] && echo "Disk at $used% on $(hostname)"
  ```

  With `MAILTO=you@example.com` at the top of the crontab and a mail setup, cron emails whatever a
  job prints; otherwise point it to a webhook with `curl`.
- **Backups that silently stopped** are the classic disaster: have the backup script ping a
  heartbeat URL (Healthchecks.io) on success, which alerts you when the ping doesn't arrive.

## Protecting staging with a password (basic auth)

Keeps search engines and strangers out of a staging site, on top of the app's own login.

```bash
cd /srv/nginx-proxy
mkdir -p conf/htpasswd
docker run --rm -it httpd:2.4-alpine htpasswd -nB client > conf/htpasswd/app.example.com
# asks for the password twice; the file holds only a hash
```

In the site's `server` block (HTTPS one), and only there:

```nginx
    auth_basic "Staging";
    auth_basic_user_file /etc/nginx/conf.d/htpasswd/app.example.com;
    add_header X-Robots-Tag "noindex, nofollow" always;
```

nginx loads only `*.conf` from `conf.d`, so the `htpasswd/` folder is safe there. Test, reload.

- **Undo:** remove the three lines, test, reload.

## Limiting login attempts (rate limiting)

If the app doesn't throttle its login, nginx can:

```nginx
# At the top of your .conf, outside any server block. The zone name must be unique on the server:
# prefix it with your project, or nginx -t fails with "duplicate zone".
limit_req_zone $binary_remote_addr zone=my_app_login:10m rate=10r/m;

server {
    # … inside the HTTPS server block:
    location = /api/auth/sign-in {             # your app's login path
        limit_req zone=my_app_login burst=5 nodelay;
        # same proxy lines as in "location /"
        resolver 127.0.0.11 valid=10s ipv6=off;
        set $upstream http://my-app:3000;
        proxy_pass $upstream;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

Too many attempts get `503`. Behind Cloudflare, use the real client IP (next section) or every
visitor shares Cloudflare's IPs.

## Behind Cloudflare's proxy

With the orange cloud ([08](08-dns.md#cloudflares-proxy-orange-cloud)), nginx sees Cloudflare's IPs,
not the visitor's. To log and rate-limit the real IP, in your `server` block:

```nginx
    real_ip_header CF-Connecting-IP;
    # Cloudflare's ranges: https://www.cloudflare.com/ips/ (update them now and then)
    set_real_ip_from 173.245.48.0/20;
    set_real_ip_from 103.21.244.0/22;
    # … one line per range
```

And SSL mode **Full (strict)**, never "Flexible" ([14](14-troubleshooting.md#logins-dont-stick--redirect-loops)).

## Wildcard certificates (`*.example.com`)

The HTTP challenge can't issue wildcards; they need the **DNS challenge**: certbot creates a TXT
record through your DNS provider's API. Worth it only when you create many subdomains (one per
client, preview environments). Example with Cloudflare:

```bash
# A token in Cloudflare with "Zone → DNS → Edit" on that zone only, saved on the server:
mkdir -p /srv/nginx-proxy/secrets && chmod 700 /srv/nginx-proxy/secrets
nano /srv/nginx-proxy/secrets/cloudflare.ini      # dns_cloudflare_api_token = <token>
chmod 600 /srv/nginx-proxy/secrets/cloudflare.ini

docker run --rm \
  -v /srv/nginx-proxy/certbot/conf:/etc/letsencrypt \
  -v /srv/nginx-proxy/secrets:/secrets:ro \
  certbot/dns-cloudflare certonly --dns-cloudflare \
  --dns-cloudflare-credentials /secrets/cloudflare.ini \
  -d example.com -d '*.example.com' --dry-run
```

Without `--dry-run` once the rehearsal passes. Renewal uses the same image and credentials, so the
renewal cron must call `certbot/dns-cloudflare` for this certificate. Other providers have their
own images (`certbot/dns-route53`, `certbot/dns-digitalocean`…).

## Several servers, one person

- Keep one private note per server: IP, provider, OS, what runs there, where each `.env` is, how
  backups leave it, when you last updated it.
- `~/.ssh/config` with a short name per server ([01](01-ssh-access.md#a-short-name-for-the-server)).
- Same layout everywhere (`/srv/apps`, `/srv/nginx-proxy`, `proxy-network`): the commands in this
  guide then work unchanged on all of them.
