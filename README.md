# Deployment guide

How to put a web application on a Linux server with Docker, nginx and HTTPS, explained from
scratch, step by step, without breaking what is already running there.

It works for any project (Next.js, Node, Python, PHP, Go…) and any server (your own VPS, a borrowed
one, a client's). Examples use made-up names such as `my-app` and `app.example.com`: replace them
with yours.

## How to use this guide

- **First time:** read [Concepts](docs/00-concepts.md), then follow
  [Deploy step by step](docs/10-deploy-step-by-step.md) from start to finish.
- **You know the basics:** go straight to the [checklists](checklists/) and the
  [templates](templates/).
- **Something broke:** [Troubleshooting](docs/14-troubleshooting.md).
- **You just need a command:** [Cheat sheet](docs/cheat-sheet.md).
- **From a Claude session:** ask it to read this repository (or paste the link).
  [CLAUDE.md](CLAUDE.md) tells it how to work with you on a server safely.

## Contents

| # | Topic | What for |
| --- | --- | --- |
| 00 | [Concepts](docs/00-concepts.md) | What each piece is: server, container, proxy, DNS, certificate |
| 01 | [SSH access](docs/01-ssh-access.md) | Getting in, keys, tunnels, copying files |
| 02 | [Server inventory](docs/02-inventory.md) | Understanding what is there before touching anything |
| 03 | [Preparing the app](docs/03-preparing-the-app.md) | What your app needs to live in a container |
| 04 | [Docker Compose](docs/04-docker-compose.md) | App + database + networks + volumes |
| 05 | [Getting the image to the server](docs/05-image-and-registry.md) | Build on the server or pull from a registry |
| 06 | [nginx as a reverse proxy](docs/06-nginx-proxy.md) | One domain → one container, no published ports |
| 07 | [HTTPS with certbot](docs/07-https-certbot.md) | Free certificate in two phases, and renewal |
| 08 | [DNS](docs/08-dns.md) | Pointing a domain or subdomain at the server |
| 09 | [Seeing the app without a domain](docs/09-without-a-domain.md) | Testing before DNS exists |
| 10 | [Deploy step by step](docs/10-deploy-step-by-step.md) | The whole procedure, with checkpoints |
| 11 | [Updates and rollback](docs/11-updates-and-rollback.md) | New versions and going back |
| 12 | [Backups](docs/12-backups.md) | Backing up and restoring the database |
| 13 | [Retiring a project](docs/13-retiring-a-project.md) | Shutting down and cleaning up without hurting others |
| 14 | [Troubleshooting](docs/14-troubleshooting.md) | 502s, certificates, restarting containers… |
| 15 | [Security](docs/15-security.md) | Secrets, firewall, access |
| — | [Cheat sheet](docs/cheat-sheet.md) | The most used commands on one page |

## The model in one picture

```text
Internet
   │  https://app.example.com
   ▼
┌──────────────────────────────── Server ─────────────────────────────────┐
│                                                                         │
│  nginx (container; the only one that opens ports 80 and 443)            │
│    ├─ app.example.com    ──► my-app:3000        (by container name)     │
│    ├─ other.example.com  ──► other-app:8080                             │
│    └─ …                                                                 │
│         ▲ all of them on the shared Docker network "proxy-network"      │
│                                                                         │
│  my-app ──(project's internal network)──► my-app-db (Postgres)          │
│                                           └─ volume holding the data    │
└─────────────────────────────────────────────────────────────────────────┘
```

- **One nginx** receives all traffic and routes it by domain name.
- **Each project** lives in its own folder with its own `docker-compose.yml`, and its containers
  **publish no ports**: nginx reaches them by name through a shared network.
- **The database** sits only on the project's internal network: from the internet it doesn't exist.
- **HTTPS** is handled by nginx with free Let's Encrypt certificates (certbot).

## Golden rules

1. **Look first, touch later.** Take the inventory before changing anything.
2. **Only your folder and your nginx file.** Don't edit other projects' things.
3. **`nginx -t` before every reload, and reload, never restart.** A restart with a config error takes
   down every site on the server at once.
4. **No global cleanup commands** (`docker system prune`, `docker volume prune`,
   `docker network prune`) on a shared server.
5. **`docker compose down` without `-v`**, unless you mean to delete the data.
6. **Every step has a way back.** If you don't know how to undo it, don't do it yet.
7. **Secrets don't go into git** or chats: they live in a `.env` file on the server.
