# New server (from scratch)

Details for each step in [16 · A server from scratch](../docs/16-server-from-scratch.md) and
[17 · The shared proxy from scratch](../docs/17-shared-proxy-from-scratch.md).

## The server

- [ ] LTS OS, enough RAM/disk, architecture noted (amd64/arm64)
- [ ] IP, provider firewall and snapshots noted from the panel
- [ ] System updated; rebooted if `/var/run/reboot-required`
- [ ] Hostname and time zone set; clock synchronized
- [ ] My user with `sudo` and my SSH key; checked in a **second** session
- [ ] `00-hardening.conf`: no passwords, no root → `sshd -t` → reload → checked from a new session
- [ ] ufw: 22, 80, 443 only → enabled → new SSH session still works
- [ ] Provider firewall: 22, 80, 443 open
- [ ] fail2ban `sshd` jail active
- [ ] unattended-upgrades on
- [ ] Swap (≤ 2 GB RAM)
- [ ] Docker from the official repo: `hello-world`, `docker compose version`, enabled at boot
- [ ] Docker log rotation (`daemon.json`)
- [ ] `/srv/apps`, `/srv/nginx-proxy`, network `proxy-network`

## The proxy

- [ ] Nothing else on 80/443 (`ss -tlnp`)
- [ ] `conf/`, `certbot/www`, `certbot/conf`; compose from the template; `config -q` OK
- [ ] `conf/00-default.conf` (unknown names get nothing)
- [ ] nginx `Up`, `nginx -t` OK; `curl -I http://<ip>` → empty reply
- [ ] Challenge test file reachable from outside
- [ ] Renewal cron in root's crontab

## After

- [ ] Snapshot of the clean server
- [ ] Private note: IP, provider, user, key, what was configured
- [ ] External port scan shows only 22, 80, 443
- [ ] First project: [New deployment](new-deployment.md)
