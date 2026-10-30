# 00 · Concepts

The vocabulary you need, in the order you meet it. Each item says what it is and why it matters
for a deployment.

## The server

- **Server / VPS:** a Linux computer that is always on and has a **public IP** (for example
  `203.0.113.10`). A VPS ("virtual private server") is a slice of a bigger machine rented from a
  provider. You don't see its screen: you control it from a terminal over SSH.
- **root:** the Linux administrator user. It can do anything, including breaking everything. On a
  server you share or borrowed, act as if every command were permanent.
- **Port:** a numbered door on an IP. A program "listens" on a port and receives what arrives
  there. Known ones: `22` SSH, `80` HTTP, `443` HTTPS, `5432` Postgres, `3000` the usual Node dev
  server. **Only one program can listen on a given port of the same IP.**
- **Firewall:** the rules that decide which ports are reachable from outside. Docker has a catch
  here (see [Security](15-security.md)): a port published by Docker can be open even if the
  firewall says otherwise.

## Docker

- **Image:** a sealed package with your app and everything it needs (Node, libraries, your built
  code). It's built once from a `Dockerfile` and doesn't change. It has a name and a **tag**
  (version): `ghcr.io/me/my-app:1.4.0`.
- **Container:** an image running. You can stop it, delete it and create it again from the same
  image; **whatever it wrote inside is lost** when it's deleted, unless it wrote into a volume.
- **Volume:** a folder managed by Docker that survives the container. **The database data lives
  here.** Deleting a volume deletes the data.
- **Docker network:** a private network between containers. Containers on the same network reach
  each other **by name** (`http://my-app:3000`, `postgres://my-app-db:5432`). A container can be on
  several networks.
- **Publishing a port** (`ports: "8080:3000"`): opens port 8080 **on the server** and forwards it to
  port 3000 of the container. Without it, the container is reachable only from its Docker networks.
  In this guide's model, **only nginx publishes ports**.
- **Docker Compose:** a `docker-compose.yml` file that describes a project's containers, networks
  and volumes, so you start everything with `docker compose up -d`. The **compose project** is
  named after the folder (or the `name:` key), and that name prefixes networks and volumes.
- **Registry:** a place to store images (Docker Hub, GitHub Container Registry `ghcr.io`, …). Your
  CI builds and pushes; the server pulls.

## The web side

- **Domain / subdomain:** `example.com` is a domain; `app.example.com` is a subdomain. You rent the
  domain from a registrar; subdomains are free and you create as many as you like.
- **DNS:** the internet's phone book. An **A record** says "`app.example.com` is at
  `203.0.113.10`". Changes take minutes to hours to spread (**propagation**; the **TTL** says how
  long others cache the old answer).
- **Reverse proxy:** a program (nginx here) that receives every request on ports 80/443 and passes
  it to the right app depending on the requested domain (`server_name`). It lets many apps share one
  server and one IP.
- **HTTPS / TLS certificate:** what makes the padlock. A certificate proves that the server really
  is `app.example.com`. **Let's Encrypt** gives them for free and **certbot** is the tool that asks
  for them. They last 90 days and must be **renewed**.
- **ACME challenge (webroot):** how Let's Encrypt checks you control the domain: it asks for a file
  at `http://app.example.com/.well-known/acme-challenge/<token>`, and certbot puts it there. That's
  why **DNS must already point to the server** and port 80 must work before you can get a
  certificate.

## The application

- **Environment variables (`.env`):** settings and secrets the app reads on startup (database URL,
  keys, public URL). They change per environment and **never go into git**.
- **Environment:** a copy of the system for a purpose: *local* (your computer), *staging* (testing,
  with fake or copied data, for the client to try) and *production* (the real one).
- **Migrations:** scripts that create or change the database tables. They run when deploying a
  version that needs them, **before** the new version starts serving.
- **Healthcheck:** a URL or command that answers "I'm OK" (for example `GET /api/health` → 200). It
  lets Docker and you know if the app really started.
- **Logs:** what the app prints. In Docker you read them with `docker logs <container>`.

## How a request flows

```text
browser ──► DNS: where is app.example.com? ──► 203.0.113.10
browser ──► 203.0.113.10:443 ──► nginx container
nginx: server_name app.example.com → proxy_pass http://my-app:3000
nginx ──(proxy-network)──► my-app container ──(internal network)──► my-app-db
```

Each arrow is something that can fail. When something doesn't work, walk the arrows in order
([Troubleshooting](14-troubleshooting.md) does exactly that).
