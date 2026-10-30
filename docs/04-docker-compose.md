# 04 · Docker Compose

One `docker-compose.yml` per project describes its containers, networks and volumes. The full
template is in [templates/docker-compose.yml](../templates/docker-compose.yml); here is why each part
is the way it is.

## The project folder

```text
/srv/apps/my-app/            ← follow the server's convention (see the inventory)
├── docker-compose.yml
├── .env                     ← secrets; chmod 600; never in git
└── backups/                 ← database dumps (see Backups)
```

## The file, explained

```yaml
name: my-app                      # compose project name: prefixes networks and volumes

services:
  app:
    image: ghcr.io/me/my-app:1.0.0   # a fixed version, not "latest" (see Updates)
    container_name: my-app           # the name nginx will use; must be unique on the server
    restart: unless-stopped          # comes back after a crash or a server reboot
    env_file: .env                   # the app's variables
    depends_on:
      db:
        condition: service_healthy   # wait for Postgres to really accept connections
    networks:
      - internal                     # to talk to its database
      - proxy-network                # so nginx can reach it
    # No "ports:". nginx reaches it as http://my-app:3000 over proxy-network.

  db:
    image: postgres:16-alpine
    container_name: my-app-db
    restart: unless-stopped
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - db-data:/var/lib/postgresql/data   # the data survives the container
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $${POSTGRES_USER} -d $${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - internal                     # ONLY the internal network: invisible to nginx and the internet

volumes:
  db-data:                           # real name: my-app_db-data

networks:
  internal:                          # created by this project: my-app_internal
  proxy-network:
    external: true                   # already exists; this project only joins it
```

### Why no `ports:`

- A published port opens the app **directly to the internet**, without HTTPS and skipping nginx.
- Docker publishes ports **past the firewall** (see [Security](15-security.md)), so "the firewall
  closes it" isn't true.
- Two projects can't publish the same port; container names on a shared network don't collide on
  ports at all.

The only exception is temporary: to see the app before having a domain
([09](09-without-a-domain.md)), and preferably bound to `127.0.0.1`.

### Why two networks

- `internal` is private to the project: the app and its database talk there. Other projects'
  containers can't see your database.
- `proxy-network` is shared with nginx: only the app joins it, not the database.

### `${VARIABLE}` and `$${VARIABLE}`

- Compose replaces `${POSTGRES_USER}` with the value from the `.env` file **next to the compose
  file** when it reads the YAML.
- `$$` escapes it so the value is read **inside the container** at run time (needed in
  `healthcheck` commands).
- `env_file: .env` passes the whole file to the container as environment variables. One `.env`
  serves both purposes.

### The `.env`

```bash
# Database (also used by the db service above)
POSTGRES_DB=my_app
POSTGRES_USER=my_app
POSTGRES_PASSWORD=<generate: openssl rand -hex 24>

# App
DATABASE_URL=postgres://my_app:<same password>@my-app-db:5432/my_app
APP_URL=https://app.example.com
SESSION_SECRET=<generate: openssl rand -base64 32>
```

- In `DATABASE_URL` the host is **the database container's name** (`my-app-db`), not `localhost`.
- Generate secrets on the server (`openssl rand -hex 24`) and use only letters and numbers in
  passwords that go inside URLs (or URL-encode them).
- Protect it: `chmod 600 .env`.

## Everyday commands (run inside the project folder)

```bash
docker compose config            # shows the final YAML with variables replaced: catches typos
docker compose pull              # downloads the images
docker compose up -d             # creates/updates and starts in the background
docker compose ps                # state of this project's containers
docker compose logs -f app       # app logs, live (Ctrl+C to leave)
docker compose restart app       # restarts only the app
docker compose stop              # stops without deleting
docker compose down              # deletes containers and the project's networks; KEEPS volumes
docker compose exec db psql -U my_app my_app   # a psql console in the database
```

**`docker compose down -v` deletes the volumes, meaning the database.** Never use it unless you
mean it.

Always run compose commands **from the project's folder** (or with `-f path/docker-compose.yml`):
run in the wrong folder, they act on another project.

## Several environments on one server

Staging and production of the same app: two folders, two `name:`, two `container_name` sets, two
`.env`, two domains. They share nothing, so you can break staging without touching production.

```text
/srv/apps/my-app-staging/   name: my-app-staging   container_name: my-app-staging, my-app-staging-db
/srv/apps/my-app/           name: my-app           container_name: my-app, my-app-db
```

## Limits (optional, recommended on shared servers)

```yaml
    deploy:
      resources:
        limits:
          memory: 768M     # a memory leak in your app can't take the whole server down
    logging:
      driver: json-file
      options:
        max-size: "10m"    # logs don't fill the disk
        max-file: "3"
```
