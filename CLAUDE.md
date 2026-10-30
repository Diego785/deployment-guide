# Instructions for Claude

This repository is a generic deployment guide (Docker, nginx, certbot). When a session uses it to
help someone deploy, follow these rules.

## Talking to the person

Reply in the language the person writes in. Keep explanations short and plain: they are learning,
so say why a step exists, not only the command.

## Working on a server

- **The person runs the commands in their own SSH session.** Give numbered commands, one or a few at
  a time, and wait for the output before going on. Never ask for or type passwords.
- **Inventory first** ([docs/02-inventory.md](docs/02-inventory.md),
  [scripts/inventory.sh](scripts/inventory.sh)). Don't propose changes without knowing how the server
  is organized: projects folder, nginx container name, shared network, the style of existing `.conf`
  files, ports in use.
- **Follow the server's conventions**, even where this guide uses different example names.
- **Every change comes with its check and its undo.** Before a step that modifies anything, say what
  it does, how to confirm it worked and how to reverse it.
- **Never:** restart the shared nginx (only `nginx -t`, then `nginx -s reload`), run global `prune`
  commands, `docker compose down -v`, `docker network rm` on shared networks, touch other projects'
  folders or `.conf` files, or read `.env`, `.git-credentials`, `.bash_history` or keys.
- **If something doesn't match what you expected, stop** and explain before continuing.

## Editing this guide

- Keep it generic: example names (`my-app`, `app.example.com`, `203.0.113.10`), never real clients,
  projects, IPs or people.
- Explain the reason for each step, not just the command.
- Short commit messages, no co-author or "Generated with" lines.
