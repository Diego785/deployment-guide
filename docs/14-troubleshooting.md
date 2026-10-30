# 14 · Troubleshooting

Walk the request's path in order and find the first link that fails:

```text
DNS → port 80/443 open → nginx has a server for the domain → nginx reaches the container → the app answers → the app reaches its database
```

| Link | Test |
| --- | --- |
| DNS | `nslookup app.example.com 1.1.1.1` → the server's IP? |
| Port | `curl -I http://203.0.113.10` from your computer answers anything? |
| nginx server | `curl -I -H "Host: app.example.com" http://127.0.0.1/` on the server → your app or another site? |
| nginx → app | `docker exec nginx curl -s http://my-app:3000/api/health` |
| App | `docker compose ps`, `docker compose logs --tail 100 app` |
| App → DB | `docker compose logs db`; `docker compose exec app env | grep DATABASE_URL` points to `my-app-db`? |

## By symptom

### `502 Bad Gateway`

nginx works but couldn't reach the app.

- The app isn't running or keeps restarting: `docker compose ps`, logs.
- The app isn't on the shared network: `docker network inspect proxy-network --format '{{range .Containers}}{{.Name}} {{end}}'`.
- Wrong name or port in `proxy_pass` (container name, not service name; the port **inside** the
  container).
- The app listens on `localhost` instead of `0.0.0.0` ([03](03-preparing-the-app.md)).
- nginx has an old IP cached (plain `proxy_pass` without the `resolver` pattern) after recreating the
  container: switch to the pattern in [06](06-nginx-proxy.md); as a stopgap, `nginx -s reload`.

### `504 Gateway Timeout`

The app received the request but took too long: slow query, an external service hanging, a long
export. Look at the app's logs; raise `proxy_read_timeout` only if the long wait is legitimate.

### Another site appears, or nginx's welcome page

nginx has no `server` with your `server_name`, so it used the default one.

- Your `.conf` isn't in the mounted folder, or doesn't end in `.conf`, or wasn't reloaded.
- A typo in `server_name`.
- For HTTPS: there's no `listen 443` block for your domain yet (phase 1).

### `nginx -t` fails

Read the message: it names the file and line.

- `host not found in upstream "x"`: a `proxy_pass` with a plain hostname whose container is down.
  Use the `resolver` + variable pattern.
- `cannot load certificate … No such file`: phase 2 before the certificate exists, or a wrong
  path. Go back to phase 1.
- `duplicate "…" variable` / `a duplicate default server`: something defined twice, often a copy of
  a `.conf` left inside `conf/`.
- `unknown directive` near a line: a missing `;` on the line before.

**If the test fails because of someone else's file**, don't reload and don't fix their file:
tell the admin. Your change waits.

### The container keeps restarting (`Restarting (1)`)

```bash
docker compose logs --tail 100 app
docker inspect my-app --format '{{.State.ExitCode}} {{.State.Error}}'
```

Typical: a missing or wrong environment variable, the database not reachable, a failed migration,
exit code `137` (killed for using too much memory: check `deploy.resources.limits` or `free -h`).

### certbot fails

- `Timeout during connect` / `Connection refused`: port 80 doesn't reach nginx (firewall, provider
  panel, Cloudflare proxy on).
- `Invalid response from … 404`: nginx answers but not from the challenge folder: the `root` in
  `location /.well-known/acme-challenge/` doesn't match the folder certbot writes to (compare the
  mounts of both containers).
- `NXDOMAIN` / `DNS problem`: the DNS record doesn't exist yet or has a typo.
- `too many failed authorizations`: rate limit; wait an hour and use `--dry-run` until it passes.

### `Permission denied`

- SSH: password typed wrong (don't paste it), or the key isn't authorized.
- Docker: your user isn't in the `docker` group; use `sudo` or ask the admin.
- Files in a volume: the process in the container runs as another user; check with
  `docker compose exec app id` and `ls -ln` of the folder.

### `port is already allocated`

Something else publishes that port: `docker ps --format '{{.Names}} {{.Ports}}' | grep ':<port>'`
and `ss -tlnp | grep ':<port> '`. Pick another or, better, don't publish (use nginx).

### `pull access denied` / `unauthorized`

The image is private and the server isn't logged in, the token expired or lacks `read:packages`,
or the image name/tag is wrong ([05](05-image-and-registry.md)).

### The disk is full

```bash
df -h
docker system df                 # images, containers, volumes, build cache
du -sh /var/lib/docker/containers/*/*-json.log | sort -h | tail   # huge logs?
```

Clean what's **yours** by name. Log rotation (`logging:` options in [04](04-docker-compose.md))
prevents it. Global prunes on a shared server: ask the admin.

### Logins don't stick / redirect loops

- `APP_URL` doesn't match the real URL (http vs https, missing subdomain).
- The app doesn't trust the proxy, so it thinks requests are HTTP and sets or refuses `Secure`
  cookies: enable "trust proxy" and check nginx sends `X-Forwarded-Proto`.
- Cloudflare in "Flexible" SSL mode with an HTTPS redirect on the server: use "Full (strict)".

## Useful views

```bash
docker compose logs -f --tail 100        # all services of the project, live
docker logs --tail 100 nginx             # proxy errors (they name the upstream that failed)
docker stats                             # CPU/RAM of every container, live
docker compose exec app sh               # a shell inside the app (exit to leave)
docker exec nginx cat /etc/nginx/conf.d/app.example.com.conf    # what nginx actually has
```
