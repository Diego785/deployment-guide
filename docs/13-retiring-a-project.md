# 13 · Retiring a project

Turning off something that's no longer used, without touching anything else. Do it in stages:
**stop → wait → delete**. Stopping is reversible; deleting isn't.

## 1 · Identify it precisely

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker inspect <container> --format 'project={{index .Config.Labels "com.docker.compose.project"}} folder={{index .Config.Labels "com.docker.compose.project.working_dir"}}'
```

Write down for the project: its folder, its containers, its networks
(`docker network ls | grep <project>`), its volumes (`docker volume ls | grep <project>`) and
whether a nginx `.conf` points to it:

```bash
grep -rl "<container-name>" /srv/nginx-proxy/conf/
```

Be sure it's **yours** (or that its owner agrees). A container named `bot` in a folder of yours can
still be in use by someone.

## 2 · Is anything still using it?

```bash
docker logs --since 72h --tail 50 <container>      # recent requests?
docker stats --no-stream <container>                # CPU/RAM in use
```

Also think outside the server: an app, a webhook or a cron elsewhere calling that port or domain.

## 3 · Back up its data, if it has any

```bash
cd <project-folder>
docker compose exec -T db pg_dump -U <user> -Fc <db> > ~/retired-<project>-$(date +%F).dump
```

Copy it off the server if it might be needed again.

## 4 · Stop it (reversible)

```bash
cd <project-folder>
docker compose down           # WITHOUT -v: containers and networks go, volumes and folder stay
```

If several compose projects are nested (a project inside another's folder), stop each from **its
own** folder, innermost first.

- **Check:** `docker ps -a | grep <project>` shows nothing; the port is free
  (`ss -tln | grep ':<port> '` prints nothing); other sites still work.
- **Undo:** `docker compose up -d` in the same folder brings it back exactly as before.

If a nginx `.conf` pointed to it, remove that file now (copy it to `~` first), then
`nginx -t` and reload. With the `resolver` pattern nginx wouldn't fail without it, but a `.conf`
for a dead app is confusing and serves 502s.

## 5 · Wait

A week or two. If nobody complains, delete. If someone does, `up -d` and talk.

## 6 · Delete (irreversible)

Only that project's things, by exact name:

```bash
docker volume rm <project>_db-data                      # its volumes (the data!)
docker image rm <its-image>:<tag>                       # its images, if no other container uses them
rm -rf <project-folder>                                 # its folder (check the path twice: pwd, ls)
docker compose run --rm certbot delete --cert-name <its-domain>    # its certificate, from the proxy folder
```

And outside the server: DNS record, CI deploy jobs, registry images, secrets.

## What not to do

- `docker system prune -a`, `docker volume prune`, `docker image prune -a`, `docker network prune`:
  they delete **every** unused thing on the server, including other projects' stopped containers,
  their images (needed for a rollback) and volumes of anything currently stopped.
- `docker compose down -v` "to clean up properly": deletes the data before you know you won't need
  it.
- `rm -rf` with a variable or a relative path you haven't checked.
