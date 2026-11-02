# 15 · Security

The minimum that keeps a small server reasonably safe. On a server that isn't yours, the server
settings (SSH, firewall, updates) belong to the admin: suggest, don't change.

## Secrets

- Only in the server's `.env` (`chmod 600`) and in your password manager. Never in git, the image,
  chats, screenshots or issue trackers.
- Commit a `.env.example` with fake values, and keep `.env*` in `.gitignore` and `.dockerignore`.
- Different secrets per environment: staging must not open production.
- If one leaks (pushed to git, pasted in a chat): **rotate it**. Deleting the commit isn't enough;
  history and caches keep it.
- Registry and git tokens on the server: read-only, one purpose, with an expiry date.

## Docker and the firewall

Docker writes its own iptables rules. **A published port (`ports: "8080:3000"`) is open to the
internet even if `ufw` says it's closed.** Hence:

- Don't publish ports except nginx's 80/443.
- If you must publish something only for the server itself, bind it to loopback:
  `"127.0.0.1:8080:3000"`.
- Databases never publish ports. To look at one, use `docker compose exec db psql …` or an SSH
  tunnel to `127.0.0.1`.

Check what's exposed, from your computer (not from the server):

```bash
nmap -Pn 203.0.113.10           # or an online port scanner
```

Expected: 22, 80, 443. Anything else, find out what it is ([02](02-inventory.md)).

## SSH

Good practice for a server you administer (step by step in [16](16-server-from-scratch.md#5--lock-down-ssh)):

- Key-only login (`PasswordAuthentication no` in `/etc/ssh/sshd_config`) **after** checking your
  key works in a second session.
- `fail2ban` to block IPs that keep guessing passwords.
- Each person with their own key, so access can be removed per person.
- `root` login disabled in favour of a user with `sudo` (`PermitRootLogin prohibit-password` at
  least).

## Updates

- The OS: `apt update && apt list --upgradable`; security updates regularly (or
  `unattended-upgrades`). Kernel updates need a reboot: on a shared server, coordinated.
- Base images: rebuild your image periodically to pick up fixes in `node:22-alpine`, etc. Pin major
  versions (`postgres:16-alpine`), not `latest`.

## The application

- HTTPS everywhere (phase 2 redirects HTTP).
- Staging protected (a login, basic auth, or `X-Robots-Tag: noindex`) so it isn't indexed or used
  as if it were real.
- Real client data in staging only if the client agrees; otherwise anonymize it.
- Rate limiting on login if the framework doesn't do it (`limit_req` in nginx is an option).
- Error pages that don't print stack traces or environment variables.

## Access to someone else's server

- Ask what you may touch, and stay within it.
- Leave a trace: tell the admin what you added (folder, `.conf`, domain, cron).
- Don't read others' files, `.env`s, histories or credentials, even if `root` lets you.
- When you no longer need access, say so, so your key/password can be removed.
