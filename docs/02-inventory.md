# 02 · Server inventory

Before deploying on a server, especially one shared with other projects, find out how it is
organized. The inventory **only reads**: it changes nothing.

## Run it

1. Copy [scripts/inventory.sh](../scripts/inventory.sh) to the server (with `scp`, or open
   `nano ~/inventory.sh` on the server and paste it).
2. Read it first: it's short, and you should never run on a server something you haven't read.
3. Run it, saving the output:

   ```bash
   bash ~/inventory.sh 2>&1 | tee ~/inventory.txt
   ```

4. Bring the output to your computer (`scp my-server:inventory.txt .`) to study it calmly, or paste
   it into your Claude session.

The script never prints environment variables or `.env` files. If you share the output, still
check it doesn't contain anything private.

## What to get out of it

Answer these questions; you'll need every answer later.

| Question | Where to look | Why |
| --- | --- | --- |
| Is there room? | *Memory and disk* | An app + Postgres needs ~1 GB of RAM to be comfortable; images and builds use disk |
| Docker and Compose versions | *Docker* | `docker compose` (v2, with a space) vs. old `docker-compose` |
| Where do projects live? | `FOLDER=` of each container | Put yours next to them, following the same pattern (e.g. `/srv/apps/<project>`) |
| What's the proxy container called and where is its config? | *Reverse proxy container*, mounts | You'll add your `.conf` there |
| What's the shared network called? | *Members of each network*: the one with the proxy plus other apps | Your app must join it |
| How are existing `.conf` files written? | *Proxy configuration files* | Copy their style (resolver, headers, certificate paths) |
| Which ports are taken? | *Ports listening* and *Containers* | Avoid collisions; spot projects that publish ports when they shouldn't |
| Which names are taken? | Container, network and volume names | `container_name` is global on the server: two projects can't use the same one |
| Are certificates renewed automatically? | *Scheduled tasks*, certbot container | If not, your certificate will expire in 90 days |
| What's stopped or unused? | `STATE=exited`, old dates | Candidates to clean up, **only if they are yours** |
| Does `nginx -t` pass today? | *nginx config test* | If it already fails, don't reload anything until it's fixed; tell the admin |

## Reading the container list

```text
NAMES        IMAGE                 STATUS          PORTS
nginx        nginx:latest          Up 3 months     0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
shop-api     shop-api:latest       Up 2 weeks
shop-db      postgres:16           Up 2 weeks      5432/tcp
old-bot      old-bot:latest        Up 8 months     0.0.0.0:3300->3000/tcp
```

- `0.0.0.0:80->80/tcp`: published port, **open to the internet** (port 80 of the server → 80 of the
  container).
- `5432/tcp` with no arrow: the container listens on 5432 but it's **not published**; only reachable
  from its Docker networks. That's what you want for databases.
- `old-bot` publishes `3300` directly: reachable at `http://IP:3300` without nginx or HTTPS. Typical
  of something deployed quickly and forgotten.

## Finding which project a port belongs to

```bash
docker ps --format '{{.Names}}\t{{.Ports}}' | grep ':3300'
docker inspect <container> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

The second command gives the folder of the project's `docker-compose.yml`.

## Before moving on

Write down in a few lines: projects folder, proxy name, config folder, shared network, certificate
method and renewal, free names. That's your map for the rest of the guide.
