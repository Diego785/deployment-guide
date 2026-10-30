#!/usr/bin/env bash
# Server inventory. READ-ONLY: it creates, changes, restarts and deletes nothing.
# It never prints environment variables, .env files, passwords or keys: for containers it asks
# only for name, image, state, ports, folder and networks.
#
# Usage on the server:   bash inventory.sh 2>&1 | tee ~/inventory.txt
set -u
sec() { printf '\n===== %s =====\n' "$1"; }

sec "System"
hostname
uname -sr
uptime
(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")

sec "Memory and disk"
free -h
df -h -x tmpfs -x devtmpfs -x overlay -x squashfs 2>/dev/null

sec "Current user"
id

sec "Docker"
if ! docker info >/dev/null 2>&1; then
  echo "WARNING: docker doesn't answer for this user without sudo; the Docker sections will be empty."
fi
docker version --format 'client {{.Client.Version}} / server {{.Server.Version}}' 2>&1 | head -2
docker compose version 2>&1 | head -1

sec "Containers (all, including stopped ones)"
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1

sec "Compose projects"
docker compose ls -a 2>&1

sec "Per container (no environment variables)"
for c in $(docker ps -aq 2>/dev/null); do
  docker inspect --format 'NAME={{.Name}} | PROJECT={{index .Config.Labels "com.docker.compose.project"}} | FOLDER={{index .Config.Labels "com.docker.compose.project.working_dir"}} | STATE={{.State.Status}} since {{.State.StartedAt}} | RESTART={{.HostConfig.RestartPolicy.Name}} | NETWORKS={{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$c" 2>&1
done

sec "Docker networks"
docker network ls 2>&1

sec "Members of each user-defined network"
for n in $(docker network ls --filter type=custom --format '{{.Name}}' 2>/dev/null); do
  echo "$n: $(docker network inspect "$n" --format '{{range .Containers}}{{.Name}} {{end}}' 2>&1)"
done

sec "Docker disk usage"
docker system df 2>&1

sec "Ports listening on the server"
ss -tlnp 2>/dev/null || ss -tln 2>/dev/null

# The reverse proxy: the container publishing port 443 (usually nginx).
PROXY=$(docker ps --format '{{.Names}} {{.Ports}}' 2>/dev/null | awk '/:443->/ {print $1; exit}')
sec "Reverse proxy container"
echo "Container publishing 443: ${PROXY:-none found}"

if [ -n "${PROXY:-}" ]; then
  docker inspect "$PROXY" --format 'Image: {{.Config.Image}}' 2>&1
  echo "Mounts:"
  docker inspect "$PROXY" --format '{{range .Mounts}}  {{.Source}} -> {{.Destination}}{{println}}{{end}}' 2>&1
  PROXY_DIR=$(docker inspect "$PROXY" --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)
  echo "Compose folder: ${PROXY_DIR:-not a compose project}"

  sec "Proxy configuration files (domains and upstreams; no certificates or keys)"
  docker exec "$PROXY" sh -c 'for f in /etc/nginx/conf.d/*.conf; do echo "----- $f"; cat "$f"; done' 2>&1

  sec "Issued certificates (domain names only)"
  docker exec "$PROXY" sh -c 'ls /etc/letsencrypt/live 2>/dev/null || ls /etc/nginx/ssl/live 2>/dev/null || echo "not found in the usual paths"' 2>&1
  if [ -n "${PROXY_DIR:-}" ]; then
    ls "$PROXY_DIR"/certbot/conf/live 2>/dev/null
  fi

  sec "nginx config test (checks only, reloads nothing)"
  docker exec "$PROXY" nginx -t 2>&1
fi

sec "Scheduled tasks of this user"
crontab -l 2>&1
ls /etc/cron.d 2>/dev/null

sec "Home folder"
ls -la ~ 2>&1

sec "End of inventory"
