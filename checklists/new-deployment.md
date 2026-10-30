# New deployment

Details for each step in [10 · Deploy step by step](../docs/10-deploy-step-by-step.md).

## Before

- [ ] App ready for containers (listens on 0.0.0.0, env vars, health endpoint, migrations) — [03](../docs/03-preparing-the-app.md)
- [ ] Works locally with the same compose file
- [ ] Image in the registry with a version tag, or build plan — [05](../docs/05-image-and-registry.md)
- [ ] [Before touching a server](before-touching-a-server.md) done
- [ ] Unique names chosen: folder, compose `name`, `container_name`s, domain

## On the server

- [ ] Folder created
- [ ] `docker-compose.yml` adapted (shared network name!, no `ports:`)
- [ ] `.env` filled with generated secrets, `chmod 600`
- [ ] `docker compose config` OK
- [ ] Image pulled (registry login if private)
- [ ] Database `healthy`
- [ ] App `Up`, logs clean, `docker exec nginx curl -s http://my-app:3000/api/health` answers
- [ ] Seen through an SSH tunnel
- [ ] Phase 1 `.conf` → `nginx -t` OK → reload → `curl -H "Host: …" http://127.0.0.1/` shows my app
- [ ] DNS A record → `nslookup` returns the IP
- [ ] Certificate: dry run OK → real one OK
- [ ] Phase 2 `.conf` → `nginx -t` OK → reload → padlock, HTTP redirects, login works

## After

- [ ] `APP_URL` is the final https URL
- [ ] Backups scheduled, one restore tested, a copy off the server
- [ ] Certificate renewal exists
- [ ] No temporary ports or files left
- [ ] Deployment notes written in the project's repo
- [ ] Server admin informed (if it isn't my server)
