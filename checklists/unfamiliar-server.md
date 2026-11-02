# A server set up by someone else (or set up differently)

Details in [18 · Servers set up differently](../docs/18-servers-set-up-differently.md).

- [ ] [Before touching a server](before-touching-a-server.md) done; inventory saved
- [ ] I know what owns 80/443: proxy container / system nginx / Apache / Caddy / Traefik /
  NPM / a panel / nothing
- [ ] I'll add my site **the way that one works** (its folder, its labels, its panel), not a second
  web server
- [ ] `nginx -t` (or `apachectl configtest`, `caddy validate`) passes **before** my change; if not,
  owner told, nothing reloaded
- [ ] If the web server isn't in Docker: my app publishes only on `127.0.0.1:<free port>`
- [ ] Certificates: I know which certbot (container, apt, snap, built into the proxy) and how it
  renews; expiry dates checked
- [ ] Apps published on public ports noted; mine moved behind the proxy, others reported
- [ ] Old tools noted (Compose v1, snap Docker, unsupported OS) and reported
- [ ] Disk and memory enough for what I'll add
- [ ] Every step planned with its check and undo; reload, never restart
- [ ] Reorganizing the server (moving to the guide's model) only with the owner's OK, a snapshot
  and a way back
