# 18 · Servers set up differently

Not every server looks like this guide's model. Many already run things another way: nginx
installed directly on the system, a hosting panel, Traefik, apps answering on their own ports, a
broken config nobody fixed. This chapter tells you **how to recognize each case** and **how to
deploy without breaking what's there**.

The rule doesn't change: **adapt to the server, not the server to you.** Only reorganize a server
if it's yours (or the owner asked for it), with a snapshot and a plan to go back (last section).

## First, find out what owns ports 80 and 443

Only one program can listen on a port. Whatever holds 80/443 decides how you add a site.

```bash
sudo ss -tlnp | grep -E ':(80|443) '
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Ports}}' | grep -E ':(80|443)->'
```

| What you see | It's | Go to |
| --- | --- | --- |
| Nothing on 80/443 | Nothing serves the web yet | [17](17-shared-proxy-from-scratch.md) (if you may install a proxy) |
| `docker-proxy` and a container `nginx`/`nginx:…` | The guide's model | [10](10-deploy-step-by-step.md) |
| `users:(("nginx",…` with no `docker-proxy` | **nginx installed on the system** | [A](#a--nginx-installed-on-the-system) |
| `apache2` or `httpd` | **Apache on the system** | [B](#b--apache-on-the-system) |
| `caddy` (process or container) | **Caddy** | [C](#c--another-proxy-in-a-container-traefik-caddy-nginx-proxy-manager) |
| A container `traefik`, `jc21/nginx-proxy-manager`, `nginxproxy/nginx-proxy` | **Another proxy in a container** | [C](#c--another-proxy-in-a-container-traefik-caddy-nginx-proxy-manager) |
| `cpanel`, `plesk`, `httpd` with `lsws`/`litespeed`, `/usr/local/CyberCP`, `/www/server/panel`, a Coolify/Dokploy/CapRover container | **A hosting panel** | [D](#d--a-hosting-panel) |

The [inventory](02-inventory.md) collects all of this in its *Web servers on the system* section.

## A · nginx installed on the system

Recognize it: `systemctl status nginx` is `active`, config in `/etc/nginx/`, sites in
`/etc/nginx/sites-enabled/` (Debian/Ubuntu) or `/etc/nginx/conf.d/` (others). Certificates usually
come from certbot installed with `apt` or `snap`, in `/etc/letsencrypt/`.

The system nginx **isn't on any Docker network**, so it can't reach containers by name. Your app
publishes its port **only on the server's loopback**, and nginx proxies to `127.0.0.1`:

```yaml
# your docker-compose.yml, service app
    ports:
      - "127.0.0.1:3001:3000"     # reachable only from the server itself, never from the internet
```

Pick a free port: `sudo ss -tln | grep ':3001 '` must print nothing.

```bash
sudo nano /etc/nginx/sites-available/app.example.com
```

```nginx
server {
    listen 80;
    server_name app.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/html;           # use the webroot the other sites use (look at their files)
    }

    location / {
        proxy_pass http://127.0.0.1:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
    }
}
```

```bash
sudo ln -s /etc/nginx/sites-available/app.example.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx          # reload, never restart
curl -I -H "Host: app.example.com" http://127.0.0.1/
```

- **Check:** the `curl` answers from your app.
- **Undo:** `sudo rm /etc/nginx/sites-enabled/app.example.com && sudo nginx -t && sudo systemctl reload nginx`.

Certificate, once DNS points to the server ([08](08-dns.md)):

```bash
certbot --version || ls /snap/bin/certbot           # which certbot exists
sudo certbot certonly --webroot -w /var/www/html -d app.example.com --dry-run
sudo certbot certonly --webroot -w /var/www/html -d app.example.com
```

Then add the HTTPS `server` block by hand, as in [06, phase 2](06-nginx-proxy.md#phase-2), with
`ssl_certificate /etc/letsencrypt/live/app.example.com/fullchain.pem;` (and `privkey.pem`), test,
reload. `certbot --nginx` would write that block for you, but it **edits nginx files**; use it only
on your own file and only if the other sites were set up the same way.

Renewal: the apt/snap certbot installs a timer. Check it exists and add a reload hook if there isn't
one, so nginx picks up renewed certificates:

```bash
systemctl list-timers | grep -i certbot
ls /etc/letsencrypt/renewal-hooks/deploy/
```

If the folder has no reload script and the server is yours:

```bash
printf '#!/bin/sh\nsystemctl reload nginx\n' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
sudo certbot renew --dry-run
```

## B · Apache on the system

Recognize it: `systemctl status apache2` (Debian/Ubuntu) or `httpd` (RHEL family), sites in
`/etc/apache2/sites-available/`.

Same idea as A: your app on `127.0.0.1:<port>`, and a virtual host that proxies to it.

```bash
sudo a2enmod proxy proxy_http headers rewrite      # usually already enabled; harmless if so
sudo nano /etc/apache2/sites-available/app.example.com.conf
```

```apache
<VirtualHost *:80>
    ServerName app.example.com
    ProxyPreserveHost On
    ProxyPass        /.well-known/acme-challenge/ !
    Alias /.well-known/acme-challenge/ /var/www/html/.well-known/acme-challenge/
    ProxyPass        / http://127.0.0.1:3001/
    ProxyPassReverse / http://127.0.0.1:3001/
    RequestHeader set X-Forwarded-Proto "http"
</VirtualHost>
```

```bash
sudo a2ensite app.example.com
sudo apachectl configtest && sudo systemctl reload apache2
```

- **Check:** `configtest` says `Syntax OK`; `curl -I -H "Host: app.example.com" http://127.0.0.1/`
  answers from your app.
- **Undo:** `sudo a2dissite app.example.com && sudo apachectl configtest && sudo systemctl reload apache2`.

Certificate: `sudo certbot certonly --webroot -w /var/www/html -d app.example.com` (dry run
first), then a `<VirtualHost *:443>` with `SSLEngine on`, `SSLCertificateFile …/fullchain.pem`,
`SSLCertificateKeyFile …/privkey.pem` and the same `ProxyPass` lines plus
`RequestHeader set X-Forwarded-Proto "https"` (needs `a2enmod ssl`). Same renewal checks as in A,
with `systemctl reload apache2` in the hook.

## C · Another proxy in a container (Traefik, Caddy, Nginx Proxy Manager)

Don't add a second proxy: use the one that's there, its way.

- **Traefik** (container `traefik`): sites are declared with **labels** on each container. Copy the
  labels another project uses (`docker inspect <other-app> --format '{{json .Config.Labels}}'`),
  change the router name, the domain and the port:

  ```yaml
      labels:
        - traefik.enable=true
        - traefik.http.routers.my-app.rule=Host(`app.example.com`)
        - traefik.http.routers.my-app.entrypoints=websecure          # name used on this server
        - traefik.http.routers.my-app.tls.certresolver=letsencrypt   # name used on this server
        - traefik.http.services.my-app.loadbalancer.server.port=3000
      networks: [<traefik's network>]
  ```

  Traefik gets the certificate by itself. No `nginx -t` here: after `docker compose up -d`, check
  `docker logs --tail 50 traefik` for errors about your router.
- **Caddy**: sites in a `Caddyfile` (find it in the container's mounts). Add
  `app.example.com { reverse_proxy my-app:3000 }`, then
  `docker exec <caddy> caddy validate --config /etc/caddy/Caddyfile` and
  `docker exec <caddy> caddy reload --config /etc/caddy/Caddyfile`. Caddy gets the certificate by
  itself.
- **Nginx Proxy Manager** (`jc21/nginx-proxy-manager`): sites are added in its web panel (usually
  port 81, ideally reached through an SSH tunnel). *Add Proxy Host* → domain, forward to
  `my-app` port `3000` (your app on NPM's network), *SSL* tab → request a Let's Encrypt
  certificate.
- **nginx-proxy** (`nginxproxy/nginx-proxy`, with `acme-companion`): sites come from environment
  variables on each container (`VIRTUAL_HOST`, `VIRTUAL_PORT`, `LETSENCRYPT_HOST`). Copy what
  another project uses.

In all four, your app joins the proxy's network and publishes no ports, exactly as in the guide.

## D · A hosting panel

cPanel, Plesk, CyberPanel, aaPanel, Coolify, Dokploy, CapRover… The panel **owns** the web server,
its files and the certificates, and rewrites them on its own. Hand-made changes get overwritten or
break the panel.

- Use the panel's way to add a site: a "reverse proxy" or "Docker app" option, or an application
  type for your stack. Coolify, Dokploy and CapRover deploy Docker images themselves.
- If the panel can't proxy to a container, ask the server's owner before improvising. Never
  install a second web server on 80/443 next to a panel.

## E · Apps published straight on ports

Recognize it: `docker ps` shows `0.0.0.0:3300->3000/tcp` and the app answers at
`http://203.0.113.10:3300`, without HTTPS.

- **Not yours:** leave it. Mention it to the owner (it's exposed without HTTPS, and Docker opens the
  port even with ufw on).
- **Yours, and you want it behind the proxy:** in order, without downtime:
  1. Add the shared network to its compose and `docker compose up -d`.
  2. Add its `.conf` (phase 1), get the certificate, phase 2 ([10](10-deploy-step-by-step.md),
     steps 7–10).
  3. Once `https://` works, remove `ports:` from its compose and `docker compose up -d` again.
  4. Tell its users the new address; the old `:3300` stops answering.

## F · The proxy's config already fails

```bash
docker exec nginx nginx -t        # or: sudo nginx -t  (system nginx)
```

If it fails **before** you changed anything, nginx is still serving the last config that worked,
but **no reload will work for anyone** until it's fixed.

- Read the error: it names a file and a line. Typical: a `.conf` pointing to a certificate that was
  deleted, an upstream that no longer exists, a duplicated `map` or `limit_req_zone`.
- If the file is yours, fix it. If not, tell the owner with the exact message; don't edit others'
  files and don't reload.
- **Never restart** nginx in this state: it would not come back, taking every site down.

## G · Nothing renews certificates

```bash
# Expiry of every certificate the proxy serves (container model)
cd <proxy folder> && docker compose run --rm certbot certificates
# System certbot
sudo certbot certificates
```

If expiry dates are less than 30 days away and there is no cron or timer
([07](07-https-certbot.md#renewal)), certificates are about to expire for every site. Tell the owner
now; if the server is yours, set up the renewal from [17, step 6](17-shared-proxy-from-scratch.md#6--automatic-certificate-renewal).

## H · Old tools

- **`docker-compose` (with a hyphen)** is Compose v1, abandoned. Commands work the same with the
  hyphen; files with `version: "3"` are fine. If you administer the server, install the plugin
  ([16, step 10](16-server-from-scratch.md#10--install-docker)) and use `docker compose`.
- **Docker installed with snap** (`snap list | grep docker`): it can't see folders outside your home
  and `/srv` mounts fail. Don't mix it with the official package on the same server; ask the owner.
- **Very old OS** (out of support): `cat /etc/os-release`. Deploy if you must, but tell the owner it
  no longer gets security fixes.

## I · No room

```bash
df -h /            # disk
free -h            # memory and swap
docker system df   # what Docker uses
```

- **Disk:** clean only **your** old images (`docker image ls | grep my-app`, then
  `docker image rm` by exact tag) and your old backups. Never global prunes on a shared server.
- **Memory:** add swap if there's none and the server is yours ([16, step 9](16-server-from-scratch.md#9--swap-servers-with-2-gb-of-ram-or-less));
  set a memory limit on your containers ([04](04-docker-compose.md#limits-optional-recommended-on-shared-servers)).

## Bringing a server to the guide's model

Only on a server that's yours, or when the owner asks. Example: moving from **nginx on the system**
to the **nginx container** of [17](17-shared-proxy-from-scratch.md).

1. **Snapshot** the server. Pick a quiet hour and announce a few minutes of downtime.
2. **Inventory** every site: `ls /etc/nginx/sites-enabled/`, each one's `server_name`, upstream
   and certificate.
3. **Prepare the new proxy without starting it:** `/srv/nginx-proxy` with its compose and one
   `.conf` per site. Apps that run in containers join `proxy-network` and are reached by name;
   apps that run on the system (not in Docker) are reached with
   a plain `proxy_pass http://host.docker.internal:<port>;` (no variable: that name comes from the
   container's `/etc/hosts`, which the `resolver` trick doesn't read) and this in nginx's service:

   ```yaml
       extra_hosts:
         - "host.docker.internal:host-gateway"
   ```

   (The app must listen on an address reachable from Docker, e.g. `0.0.0.0` with ufw blocking that
   port from outside, or the Docker bridge IP.)
4. **Copy the certificates**: `sudo cp -a /etc/letsencrypt/. /srv/nginx-proxy/certbot/conf/`. The
   renewal files inside point to the old webroot: renewals must use `-w /var/www/certbot` from now
   on (`sudo certbot renew --dry-run` later, from the container, confirms it).
5. **Test the new config with the new image before switching:**

   ```bash
   cd /srv/nginx-proxy
   docker compose run --rm --no-deps nginx nginx -t      # a throwaway container: publishes nothing
   ```

6. **Switch**, in one line so the gap is seconds:

   ```bash
   sudo systemctl stop nginx && docker compose up -d nginx
   ```

7. **Check** every site with `curl -I https://<each domain>`. If anything fails, **go back**:
   `docker compose down && sudo systemctl start nginx`.
8. When everything has worked for a few days: `sudo systemctl disable nginx` (so it doesn't fight
   for port 80 after a reboot), the renewal cron from [17](17-shared-proxy-from-scratch.md#6--automatic-certificate-renewal),
   and remove the old timer (`sudo systemctl disable --now certbot.timer` or `snap.certbot.renew.timer`).
