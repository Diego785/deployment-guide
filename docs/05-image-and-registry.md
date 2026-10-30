# 05 · Getting the image to the server

The server needs your app's image. Two ways; pick one per project.

| | A. Pull from a registry | B. Build on the server |
| --- | --- | --- |
| How | CI builds and pushes; the server runs `docker compose pull` | `git clone` on the server and `docker compose build` |
| Server load | Minimal (only downloads) | CPU, RAM and disk while building; can slow down other apps |
| Source code on the server | No | Yes (plus build cache) |
| Credentials on the server | Read-only access to the registry | Read access to the git repo |
| Rollback | Change the tag, `up -d` | `git checkout` of the previous version and rebuild |
| Best for | Anything you'll update often; shared servers | Quick tests; servers that can't reach the registry |

**Recommended: A.** It's the same image you tested, built once, and the server does no heavy work.

## A. Registry (example: GitHub Container Registry)

### 1. CI publishes the image

A GitHub Actions job that builds and pushes on every push to `main` (summarized):

```yaml
# .github/workflows/image.yml
on:
  push:
    branches: [main]
    tags: ["v*"]
permissions:
  contents: read
  packages: write
jobs:
  image:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/metadata-action@v5
        id: meta
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=sha,prefix=sha-
            type=ref,event=branch
            type=semver,pattern={{version}}
      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ${{ steps.meta.outputs.tags }}
```

Result: tags like `ghcr.io/me/my-app:main`, `:sha-1a2b3c4` and, for a `v1.2.0` git tag, `:1.2.0`.
Use immutable tags (`sha-…`, `1.2.0`) on the server so you always know what's running.

### 2. The server logs in (only if the image is private)

Create a token that can **only read packages**:

- GitHub → Settings → Developer settings → Personal access tokens → **Tokens (classic)** → scope
  **`read:packages`** only, with an expiry date. (Fine-grained tokens don't cover GHCR packages
  well yet; check the current GitHub docs.)
- If the repo belongs to an organization, the package must allow your user, and the org may
  require approving the token.

On the server, once:

```bash
docker login ghcr.io -u <your-github-user>
# Password: paste the token (not your GitHub password). It's stored in ~/.docker/config.json.
```

Then `docker compose pull` works. If the token expires, pulls fail with `denied` or
`unauthorized`: create a new one and log in again.

Alternatives: make the package public (if the code can be public), or use a deploy-only machine
account.

### 3. Deploy

```bash
cd /srv/apps/my-app
# change the tag in docker-compose.yml (or in .env if you use image: ghcr.io/me/my-app:${APP_TAG})
docker compose pull app
docker compose up -d app
```

## B. Build on the server

```bash
cd /srv/apps/my-app
git clone https://github.com/me/my-app.git src     # private repo: use a deploy key or a read-only token
```

In `docker-compose.yml` replace `image:` with:

```yaml
    build:
      context: ./src
    image: my-app:local     # name for the built image
```

```bash
cd /srv/apps/my-app/src && git pull && cd ..
docker compose build app
docker compose up -d app
```

Build cache grows over time. Clean **only build cache**, never everything:

```bash
docker builder prune --filter until=168h    # cache older than 7 days; asks for confirmation
```

On a shared server, even this is worth mentioning to the admin first: the cache is shared by every
project that builds there.

### Private repo access for B

- **Deploy key** (recommended): an SSH key created on the server, added to that repo only, read-only
  (GitHub repo → Settings → Deploy keys).
- **Token**: a fine-grained token with read access to just that repo. Don't store it in the clone
  URL (`https://token@github.com/...`), because it ends up in `.git/config`.

## C. Without registry or git (emergencies)

```bash
docker save my-app:1.0.0 | gzip > my-app-1.0.0.tar.gz      # on your computer
scp my-app-1.0.0.tar.gz my-server:/tmp/
ssh my-server "gunzip -c /tmp/my-app-1.0.0.tar.gz | docker load"
```

It works, but it's manual and slow; use it only as a fallback.
