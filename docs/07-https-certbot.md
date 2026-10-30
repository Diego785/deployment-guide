# 07 · HTTPS with certbot

Let's Encrypt gives free certificates valid for 90 days. certbot requests them using the
**webroot** method: it writes a file into the folder nginx serves at
`/.well-known/acme-challenge/`, and Let's Encrypt downloads it over HTTP to confirm you control
the domain.

## Requirements (all of them, before requesting)

1. **DNS already points to the server**: `nslookup app.example.com` returns the server's IP
   ([08](08-dns.md)).
2. **Phase 1 `.conf` is loaded** (`nginx -t` OK and reloaded) and serves the challenge folder.
3. **Port 80 is reachable from the internet** (firewall/provider).

Check 2 and 3 with a test file before calling certbot:

```bash
# On the server: create a test file in the challenge folder (the HOST path of the webroot mount)
echo ok | sudo tee /srv/nginx-proxy/certbot/www/.well-known/acme-challenge/test
# From your computer:
curl http://app.example.com/.well-known/acme-challenge/test     # must print "ok"
# Clean up:
sudo rm /srv/nginx-proxy/certbot/www/.well-known/acme-challenge/test
```

If that fails, certbot will fail too. Fix this first ([Troubleshooting](14-troubleshooting.md)).

## Request the certificate

Run from the proxy's folder; the volume paths must be the same ones nginx uses.

```bash
cd /srv/nginx-proxy

# 1. Rehearsal: talks to Let's Encrypt's test server, creates nothing, has no rate limits
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  -d app.example.com --dry-run

# 2. The real one (only if the dry run said "The dry run was successful")
docker compose run --rm certbot certonly --webroot -w /var/www/certbot \
  -d app.example.com --email you@example.com --agree-tos --no-eff-email
```

If the proxy has no certbot service in its compose, the equivalent with plain Docker:

```bash
docker run --rm \
  -v /srv/nginx-proxy/certbot/www:/var/www/certbot \
  -v /srv/nginx-proxy/certbot/conf:/etc/letsencrypt \
  certbot/certbot certonly --webroot -w /var/www/certbot -d app.example.com --dry-run
```

Success says where the files are: `/etc/letsencrypt/live/app.example.com/fullchain.pem` and
`privkey.pem` (inside the container; on the host under `certbot/conf/live/…`).

**Always dry-run first.** The real server allows only 5 failed validations per hour per domain
and 5 identical certificates per week; repeated failures lock you out for a while.

## Switch to phase 2

1. Replace your `.conf` with the phase 2 version (HTTPS, 80 → 443 redirect).
2. Check that the certificate paths in it match the folder nginx mounts.
3. `docker exec nginx nginx -t` → OK → `docker exec nginx nginx -s reload`.
4. Open `https://app.example.com` and check the padlock.

## Renewal

Certificates expire in 90 days; certbot renews those with less than 30 days left.

```bash
cd /srv/nginx-proxy
docker compose run --rm certbot renew --dry-run    # rehearsal
docker compose run --rm certbot renew              # renews what's due (does nothing otherwise)
docker exec nginx nginx -s reload                  # nginx loads renewed certificates only on reload
```

**Automate it** with cron, otherwise one day every site's certificate expires:

```bash
crontab -e
```

```cron
# Every day at 03:17: renew what's due and reload nginx (logs in /var/log/certbot-renew.log)
17 3 * * * { cd /srv/nginx-proxy && docker compose run --rm certbot renew --quiet && docker exec nginx nginx -s reload; } >> /var/log/certbot-renew.log 2>&1
```

On a shared server, the proxy's renewal belongs to whoever runs the proxy. If the inventory shows
no renewal job, tell the admin instead of adding one on your own: it renews **every** certificate.

## Checking a certificate

```bash
# Expiry date of what's being served
echo | openssl s_client -connect app.example.com:443 -servername app.example.com 2>/dev/null \
  | openssl x509 -noout -dates -subject
# Everything certbot manages
docker compose run --rm certbot certificates
```

## Removing a certificate (when retiring a domain)

```bash
docker compose run --rm certbot delete --cert-name app.example.com
```

Remove the `.conf` that references it **first** (and reload), or nginx will fail the next test.
