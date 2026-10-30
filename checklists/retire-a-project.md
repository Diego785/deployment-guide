# Retire a project

Details in [13 · Retiring a project](../docs/13-retiring-a-project.md).

## Stop (reversible)

- [ ] Containers, folder, networks, volumes, `.conf` and domain of the project listed
- [ ] Confirmed it's mine / the owner agrees, and nothing still uses it (logs, other systems)
- [ ] Data backed up and copied off the server
- [ ] `docker compose down` (no `-v`) from its own folder; nested projects innermost first
- [ ] Its `.conf` copied out and removed → `nginx -t` → reload
- [ ] Other sites still work; the port is free

## Wait

- [ ] One or two weeks without complaints

## Delete (irreversible)

- [ ] Its volumes, by exact name
- [ ] Its images, by exact name
- [ ] Its folder (path checked twice)
- [ ] Its certificate (`certbot delete --cert-name …`)
- [ ] Outside the server: DNS record, CI jobs, registry images, secrets
