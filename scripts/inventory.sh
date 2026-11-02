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

# Who owns 80/443 decides how a site is added (docs/18-servers-set-up-differently.md).
sec "Web servers on the system (outside Docker)"
for svc in nginx apache2 httpd caddy lsws lshttpd traefik; do
  state=$(systemctl is-active "$svc" 2>/dev/null)
  [ "$state" = "active" ] && echo "service $svc: active"
done
[ -d /etc/nginx/sites-enabled ] && echo "/etc/nginx/sites-enabled: $(ls /etc/nginx/sites-enabled 2>/dev/null | tr '\n' ' ')"
[ -d /etc/apache2/sites-enabled ] && echo "/etc/apache2/sites-enabled: $(ls /etc/apache2/sites-enabled 2>/dev/null | tr '\n' ' ')"
command -v certbot >/dev/null 2>&1 && echo "certbot on the system: $(command -v certbot)"
systemctl list-timers --all 2>/dev/null | grep -i certbot
echo "(nothing listed above = no web server installed on the system)"

sec "Hosting panels and other proxies"
for path in /usr/local/cpanel /usr/local/psa /usr/local/CyberCP /www/server/panel /data/coolify /etc/dokploy; do
  [ -e "$path" ] && echo "found: $path"
done
docker ps --format '{{.Names}} {{.Image}}' 2>/dev/null \
  | grep -Ei 'traefik|caddy|nginx-proxy-manager|nginxproxy|jwilder|coolify|dokploy|caprover|portainer' \
  || echo "no known proxy or panel container"

sec "Firewall"
if command -v ufw >/dev/null 2>&1; then
  ufw status 2>&1 | head -20
else
  echo "ufw not installed"
fi
echo "(ufw needs root: if it says 'need to be root', run 'sudo ufw status' by hand)"

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
