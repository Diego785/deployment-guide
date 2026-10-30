# Cheat sheet

Replace `my-app`, `nginx`, `app.example.com` and the folders with your real names.

## Connect

```bash
ssh root@203.0.113.10                              # or: ssh my-server (with ~/.ssh/config)
scp file my-server:/srv/apps/my-app/               # copy to the server
scp my-server:/srv/apps/my-app/backups/x.dump .    # copy from the server
ssh -N -L 8080:<container-ip>:3000 my-server       # tunnel: http://localhost:8080
```

## Look (safe, change nothing)

```bash
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
docker compose ls -a
docker network ls
docker network inspect proxy-network --format '{{range .Containers}}{{.Name}} {{end}}'
docker inspect <c> --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}'
docker logs --tail 100 <c>
docker stats --no-stream
docker system df
ss -tln
df -h && free -h
```

## Project (inside its folder)

```bash
docker compose config               # validate
docker compose pull                 # download images
docker compose up -d                # create/update and start
docker compose ps                   # state
docker compose logs -f app          # logs live
docker compose up -d app            # apply .env or tag changes to the app
docker compose restart app          # restart (doesn't re-read .env)
docker compose stop                 # stop
docker compose down                 # remove containers, KEEP data
docker compose exec app sh          # shell inside
docker compose exec db psql -U my_app my_app
```

## nginx (shared)

```bash
docker exec nginx nginx -t                 # ALWAYS first
docker exec nginx nginx -s reload          # only if -t passed
docker exec nginx curl -s http://my-app:3000/api/health
curl -I -H "Host: app.example.com" http://127.0.0.1/
docker logs --tail 50 nginx
```

**Never** `docker restart nginx` on a shared server.

## Certificates (from the proxy folder)

```bash
docker compose run --rm certbot certonly --webroot -w /var/www/certbot -d app.example.com --dry-run
docker compose run --rm certbot certonly --webroot -w /var/www/certbot -d app.example.com --email you@example.com --agree-tos --no-eff-email
docker compose run --rm certbot renew --dry-run
docker compose run --rm certbot certificates
echo | openssl s_client -connect app.example.com:443 -servername app.example.com 2>/dev/null | openssl x509 -noout -dates
```

## Database

```bash
docker compose exec -T db pg_dump -U my_app -Fc my_app > backups/my_app-$(date +%F).dump
docker compose exec -T db pg_restore -U my_app -d my_app --clean --if-exists --no-owner < backups/<file>.dump
```

## DNS

```bash
nslookup app.example.com 1.1.1.1
```

## Secrets

```bash
openssl rand -hex 24          # password
openssl rand -base64 32       # session/JWT secret
chmod 600 .env
```

## Dangerous: think twice, never on a shared server without asking

```bash
docker compose down -v        # deletes the project's volumes = its data
docker system prune -a        # deletes every unused image/container/network on the server
docker volume prune           # deletes every unused volume on the server
docker restart nginx          # a broken config takes down every site
rm -rf <folder>               # check pwd and the path twice
```
