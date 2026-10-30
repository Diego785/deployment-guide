# 06 · nginx as a reverse proxy

A single nginx container receives every request on ports 80 and 443 and passes each one to the
right app by domain name. Each project adds **one `.conf` file**; nobody touches the others.

## The typical layout

```text
/srv/nginx-proxy/                    ← the proxy's own compose project (find yours in the inventory)
├── docker-compose.yml               ← nginx (ports 80/443) + certbot (runs on demand)
├── conf/                            ← mounted at /etc/nginx/conf.d inside nginx
│   ├── shop.example.com.conf
│   ├── other.example.com.conf
│   └── app.example.com.conf         ← yours
└── certbot/
    ├── www/                         ← ACME challenge files (webroot)
    └── conf/                        ← certificates (live/, archive/, renewal/)
```

The proxy's compose file usually looks like this:

```yaml
services:
  nginx:
    image: nginx:1.27-alpine
    container_name: nginx
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./conf:/etc/nginx/conf.d
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    networks:
      - proxy-network

  certbot:
    image: certbot/certbot
    volumes:
      - ./certbot/www:/var/www/certbot
      - ./certbot/conf:/etc/letsencrypt
    profiles: ["tools"]        # not started by "up"; run on demand

networks:
  proxy-network:
    external: true
```

The paths inside the containers (`/var/www/certbot`, `/etc/letsencrypt`) vary between servers.
**Read them from the inventory's mounts and use those in your `.conf`.** Creating the shared
network for the first time, only if it doesn't exist: `docker network create proxy-network`.

## Your file, phase by phase

The certificate can't exist before nginx answers on port 80 for your domain, and nginx won't start
(or reload) with a `.conf` pointing to a certificate that doesn't exist. Hence two phases:

1. **Phase 1, HTTP only** ([templates/nginx/phase1-http.conf](../templates/nginx/phase1-http.conf)):
   serves the ACME challenge and proxies the app over HTTP.
2. Get the certificate ([07](07-https-certbot.md)).
3. **Phase 2, HTTPS** ([templates/nginx/phase2-https.conf](../templates/nginx/phase2-https.conf)):
   port 80 redirects to HTTPS; port 443 serves the app with the certificate.

### Phase 1

```nginx
server {
    listen 80;
    server_name app.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        # Docker's internal DNS. With a variable, nginx resolves the name per request:
        # it starts even if the app is down and follows the container if its IP changes.
        resolver 127.0.0.11 valid=10s ipv6=off;
        set $upstream http://my-app:3000;
        proxy_pass $upstream;

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### Phase 2

```nginx
server {
    listen 80;
    server_name app.example.com;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    http2 on;                       # nginx ≥ 1.25; on older versions: "listen 443 ssl http2;"
    server_name app.example.com;

    ssl_certificate     /etc/letsencrypt/live/app.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.example.com/privkey.pem;

    client_max_body_size 20m;       # largest upload allowed (default 1m)

    location / {
        resolver 127.0.0.11 valid=10s ipv6=off;
        set $upstream http://my-app:3000;
        proxy_pass $upstream;

        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        # WebSockets / live reload / streaming: pass the client's Upgrade and Connection headers
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $http_connection;
        proxy_read_timeout 300s;
    }
}
```

About WebSockets: the textbook version uses a `map $http_upgrade $connection_upgrade { … }` block,
but a `map` lives at `http` level, so it may be defined **only once in the whole nginx**. If two
projects' files both define it, `nginx -t` fails with `duplicate "$connection_upgrade" variable`.
Passing `$http_connection` through, as above, needs no `map` and can't collide. If you don't need
WebSockets at all, `proxy_set_header Connection "";` is enough.

## Why the `resolver` + variable trick matters

With a plain `proxy_pass http://my-app:3000;`, nginx resolves `my-app` **once, at startup**:

- If `my-app` isn't running at that moment, **nginx refuses to start or reload**:
  `host not found in upstream "my-app"`. On a shared proxy, one stopped app blocks reloads for
  everyone.
- When you recreate the container, it may get a new IP and nginx keeps using the old one → 502.

With `resolver 127.0.0.11` (Docker's embedded DNS) and `set $upstream …; proxy_pass $upstream;`,
the name is resolved at request time. A down app gives a 502 only for its own domain.

## Applying changes: test, then reload

```bash
docker exec nginx nginx -t           # 1. test: must say "syntax is ok" and "test is successful"
docker exec nginx nginx -s reload    # 2. only if 1 passed
```

- **`reload`** applies the new config without dropping connections. If the new config were wrong,
  nginx keeps the old one.
- **`docker restart nginx` / `docker compose restart nginx`**: if the config is broken, nginx
  **doesn't come back** and every site on the server goes down. Don't, on a shared server.
- If `nginx -t` fails, read the message (file and line), fix **your** file, or remove it and test
  again. Never reload with a failing test.

## Checking it works

```bash
# From the server, without depending on DNS: ask nginx for your domain explicitly
curl -I -H "Host: app.example.com" http://127.0.0.1/
# From the nginx container, check it can reach the app
docker exec nginx curl -s http://my-app:3000/api/health
# nginx's logs (errors at the end)
docker logs --tail 50 nginx
```

## Common variations

- **Static site** (no app container): `root /var/www/my-site; index index.html;` and mount the
  folder into nginx. Ask the admin; it changes the proxy's compose file.
- **Several domains to the same app**: `server_name example.com www.example.com;` and one
  certificate with both names (`-d example.com -d www.example.com`).
- **Redirect www → bare domain**: a separate `server` that only does
  `return 301 https://example.com$request_uri;`.
- **Basic password on staging** (`htpasswd`): useful so search engines and strangers don't see it.
