# 03 · Preparing the app

Before thinking about the server, make sure the app can run in a container. Most deployment
problems are really problems here.

## The checklist

- [ ] **It listens on `0.0.0.0`, not `localhost`.** Inside a container, `localhost` is only the
  container itself: nginx couldn't reach it. In Node: `HOST=0.0.0.0` or `app.listen(3000, "0.0.0.0")`;
  Next.js standalone uses `HOSTNAME=0.0.0.0`.
- [ ] **Everything configurable comes from environment variables**: database URL, secrets, public
  URL, email keys. Nothing hard-coded for one environment.
- [ ] **It has a `.env.example`** listing every variable with a fake value and a comment.
- [ ] **It has a health endpoint**, e.g. `GET /api/health` → `200` when it can reach the database,
  `503` when it can't.
- [ ] **It knows its public URL** (`APP_URL=https://app.example.com`) for links, cookies,
  redirects and authentication callbacks.
- [ ] **It trusts the proxy**: behind nginx, the request arrives over HTTP from nginx's IP. The app
  must read `X-Forwarded-Proto` / `X-Forwarded-For` to know it was HTTPS and the real client IP
  (frameworks have a "trust proxy" setting).
- [ ] **Migrations run in a controlled way**: on startup before serving, or as a separate command
  in the deploy. Never by hand on production without a backup.
- [ ] **Files that must survive** (uploads, generated documents) go to a volume or to object
  storage, never only inside the container.
- [ ] **Logs go to stdout/stderr**, not to files inside the container.
- [ ] **It shuts down cleanly** on `SIGTERM` (finishes requests, closes the database connection).
- [ ] **The image builds without secrets.** Build-time and run-time variables are different: if
  the build needs a secret, it's leaking into the image.

## A good Dockerfile (Node example)

Multi-stage: one stage installs and builds, the final one copies only what's needed to run.
Smaller image, less attack surface, faster pulls.

```dockerfile
# 1. Dependencies
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci

# 2. Build
FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# 3. Run
FROM node:22-alpine AS run
WORKDIR /app
ENV NODE_ENV=production HOST=0.0.0.0 PORT=3000
# Don't run as root inside the container
RUN addgroup -S app && adduser -S app -G app
COPY --from=build --chown=app:app /app/dist ./dist
COPY --from=build --chown=app:app /app/node_modules ./node_modules
COPY --from=build --chown=app:app /app/package.json ./
USER app
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health || exit 1
CMD ["node", "dist/server.js"]
```

Notes:

- **Next.js:** with `output: "standalone"` in `next.config`, copy `.next/standalone`,
  `.next/static` (to `.next/static`) and `public`, and run `node server.js`. The image goes from
  ~1 GB to ~150 MB.
- **pnpm/yarn:** enable Corepack (`RUN corepack enable`) and use the lockfile with
  `--frozen-lockfile`.
- **Migrations on startup:** a small `entrypoint.sh` that runs the migration and then
  `exec node server.js` (`exec` so the app receives `SIGTERM`).
- **`.dockerignore`** is mandatory: `node_modules`, `.next`, `.git`, `.env*`, `coverage`… Without it
  you copy gigabytes and maybe your secrets into the image.

## Try it locally first

Everything that fails on the server can be found on your computer, much more cheaply:

```bash
docker build -t my-app:test .
docker run --rm -p 3000:3000 --env-file .env.local my-app:test
# Another terminal:
curl -i http://localhost:3000/api/health
```

Even better, run the same `docker-compose.yml` you'll use on the server (with a local `.env`). If
it works locally with compose, the server only adds nginx and DNS.

## Size and architecture

- `docker images my-app` shows the size. Over 1 GB for a web app usually means a missing
  multi-stage or `.dockerignore`.
- If you build on an ARM Mac and the server is x86 (almost always), build with
  `docker build --platform linux/amd64 …` or let CI build it.
