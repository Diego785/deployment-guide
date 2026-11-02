# 16 · A server from scratch

What to do with a brand-new Linux server (VPS, VDS, dedicated) before deploying anything: get in
safely, lock it down, install Docker. When you finish, continue with
[17 · The shared proxy from scratch](17-shared-proxy-from-scratch.md) and then
[10 · Deploy step by step](10-deploy-step-by-step.md).

This chapter is for a server **that is yours** (you or your client rent it, nobody else runs things
on it). On a server that already has projects, don't apply it: take the [inventory](02-inventory.md)
and read [18 · Servers set up differently](18-servers-set-up-differently.md).

Example values: server `203.0.113.10`, your user `deploy`. Commands assume **Ubuntu 24.04 or 22.04
LTS** or **Debian 12**; the differences are noted.

## 0 · Choosing the server

| | Small (1 app + Postgres, few users) | Medium (2–4 apps, or a busy one) |
| --- | --- | --- |
| CPU | 1–2 vCPU | 2–4 vCPU |
| RAM | 2 GB (1 GB works with swap, tight) | 4–8 GB |
| Disk | 25–40 GB SSD | 80 GB+ SSD |

- **OS:** an **LTS** release (Ubuntu 24.04 LTS or Debian 12). Avoid non-LTS versions: they stop
  getting security fixes in months.
- **VPS vs VDS:** a VDS gives you dedicated CPU cores, a VPS shares them. For a small business app
  a VPS is enough; a VDS pays off with heavy, steady load.
- **Architecture:** most are `x86_64` (`amd64`). If you pick an ARM server (`aarch64`), your image
  must be built for ARM too ([05](05-image-and-registry.md)).
- **From the provider's panel, write down:** the public IP, the root password or the SSH key you
  chose, whether there is a **provider firewall** (a firewall in the panel, outside the server) and
  whether it offers **snapshots** or **backups** of the whole server.
- Take the habit of a **snapshot before any big change** (OS upgrade, firewall, SSH config): it's
  the fastest undo there is.

## 1 · First login

```bash
ssh root@203.0.113.10
```

The first time, SSH asks to confirm the server's fingerprint: type `yes`. If you chose a key in the
panel, it logs in without a password; otherwise it asks for the root password the provider gave
you.

- **Check:** the prompt shows `root@…`. `cat /etc/os-release` shows the OS you chose.
- If the provider forces a password change on first login, do it and store the new one in your
  password manager.

## 2 · Update the system

```bash
apt update && apt full-upgrade -y
[ -f /var/run/reboot-required ] && echo "reboot needed"
```

If it says `reboot needed` (a new kernel), reboot now: nothing is running yet, so it costs nothing.

```bash
reboot            # the connection drops; wait ~1 minute and ssh in again
```

- **Check:** `apt list --upgradable` is empty or almost.
- **Undo:** not needed; if something went badly, the provider's snapshot or rescue console.

## 3 · Name, time zone and basic tools

```bash
hostnamectl set-hostname my-server
timedatectl set-timezone UTC          # or your zone: timedatectl list-timezones | grep -i <city>
apt install -y curl ca-certificates nano htop git unzip
```

- **Time zone:** UTC avoids surprises with daylight saving and makes logs comparable between
  servers. Choose your local zone if cron times (backups at 3 a.m.) should be local; either works,
  just know which one you chose.
- **Check:** `hostnamectl` and `timedatectl` show the new values; `timedatectl` says
  `System clock synchronized: yes`.

## 4 · A user for you (and stop using root)

Working as root makes every mistake total. Create your user and give it `sudo`:

```bash
adduser deploy                 # asks for a password: generate a long one and store it
usermod -aG sudo deploy        # members of "sudo" can run commands as root with sudo
```

Copy your SSH key to it. If root already logs in with your key:

```bash
rsync --archive --chown=deploy:deploy ~/.ssh /home/deploy
```

If you still log in as root with a password, first create a key on your computer and copy it
([01 · SSH keys](01-ssh-access.md#ssh-keys-better-than-a-password)), using `deploy@203.0.113.10` as
the destination.

- **Check, in a NEW terminal, without closing the current one:**

  ```bash
  ssh deploy@203.0.113.10
  sudo whoami          # asks for deploy's password, prints "root"
  ```

- **Undo:** `deluser --remove-home deploy`.

From now on, log in as `deploy` and use `sudo` for administrative commands.

## 5 · Lock down SSH

Only once step 4's check passed (you can log in as `deploy` **with the key** and use `sudo`).
Keep your current session open the whole step: if something goes wrong, it's your way back in.

```bash
sudo nano /etc/ssh/sshd_config.d/00-hardening.conf
```

```text
# Keys only: no password guessing possible
PasswordAuthentication no
KbdInteractiveAuthentication no
# No direct root login; use your user + sudo
PermitRootLogin no
```

Why `00-`: sshd reads the files in `sshd_config.d/` alphabetically and **the first value wins**.
Many providers ship a `50-cloud-init.conf` with `PasswordAuthentication yes`; a file starting with
`00-` is read before it.

```bash
sudo sshd -t                                                     # syntax test: prints nothing if OK
sudo sshd -T | grep -Ei '^(passwordauthentication|permitrootlogin|kbdinteractiveauthentication)'
sudo systemctl reload ssh                                        # only if the test passed
```

- **Check:** `sshd -T` shows `passwordauthentication no`, `permitrootlogin no`,
  `kbdinteractiveauthentication no`. Then, **from a new terminal**:
  - `ssh deploy@203.0.113.10` works with your key.
  - `ssh root@203.0.113.10` is refused.
  - `ssh -o PubkeyAuthentication=no deploy@203.0.113.10` says `Permission denied (publickey)`.
- **Undo:** `sudo rm /etc/ssh/sshd_config.d/00-hardening.conf && sudo systemctl reload ssh` from the
  session you kept open. If you got locked out: the provider's web console (VNC/"Console") logs you
  in as if you were at the screen.

Changing the SSH port (22 → another) only reduces log noise; it's not real protection and it
complicates everything else (firewall, provider firewall, socket activation on Ubuntu 24.04). Not
recommended at first.

## 6 · Firewall (ufw)

Close everything except SSH, HTTP and HTTPS. **Allow SSH before enabling**, or you lock yourself out.

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH          # port 22
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable                 # asks for confirmation: y
sudo ufw status verbose
```

- **Check:** `status` shows `Status: active` with 22, 80 and 443 allowed (also `(v6)`), and a new SSH
  session still works.
- **Undo:** `sudo ufw disable`.

Two things to know:

- **Docker bypasses ufw** for published ports ([15](15-security.md#docker-and-the-firewall)). That's
  fine in this guide's model, because only nginx publishes ports (80/443), which are allowed anyway.
  Never publish a database port "temporarily".
- **The provider's firewall** (in its panel) is a second door in front of the server. If it exists,
  open 22, 80 and 443 there too, or Let's Encrypt won't reach port 80.

## 7 · Block password guessers (fail2ban)

With passwords off, guessing can't succeed, but fail2ban still blocks the noise and protects you if
password login is ever turned back on.

```bash
sudo apt install -y fail2ban python3-systemd   # python3-systemd: reads SSH logs from journald
sudo nano /etc/fail2ban/jail.local
```

```ini
[sshd]
enabled = true
backend = systemd
maxretry = 5
bantime = 1h
```

```bash
sudo systemctl enable --now fail2ban
sudo fail2ban-client status sshd
```

- **Check:** `status sshd` lists the jail (with `Currently banned: 0` at first).
- **Undo:** `sudo systemctl disable --now fail2ban`.
- **If you ban yourself** (typing a wrong key many times): from another IP or the provider's console,
  `sudo fail2ban-client set sshd unbanip <your-ip>`.

## 8 · Automatic security updates

```bash
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades      # answer "Yes"
cat /etc/apt/apt.conf.d/20auto-upgrades
```

- **Check:** the file contains `APT::Periodic::Unattended-Upgrade "1";`.
- They install **security** updates only, daily. Kernel updates still need a reboot: check
  `/var/run/reboot-required` now and then (e.g. monthly) and reboot at a quiet hour. Your containers
  come back by themselves if they have `restart: unless-stopped`.

## 9 · Swap (servers with 2 GB of RAM or less)

Without swap, a memory spike (a build, a migration) makes Linux kill a process, often the database.
Swap is slow memory on disk that absorbs those spikes.

```bash
free -h                                   # "Swap: 0B" means there is none
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab     # keep it after reboots
echo 'vm.swappiness=10' | sudo tee /etc/sysctl.d/99-swappiness.conf && sudo sysctl --system
```

- **Check:** `free -h` shows `Swap: 2.0Gi`. `swappiness=10` makes Linux use it only when RAM is
  really short.
- **Undo:** `sudo swapoff /swapfile`, remove the line from `/etc/fstab`, `sudo rm /swapfile`.

## 10 · Install Docker

Use Docker's official repository: the `docker.io` package of the distribution is older and comes
without the `docker compose` plugin.

```bash
# Docker's signing key and repository (Ubuntu; for Debian replace "ubuntu" with "debian" twice)
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

- **Check:**

  ```bash
  sudo docker run --rm hello-world        # prints "Hello from Docker!"
  docker compose version                  # v2.x: "docker compose" with a space
  systemctl is-enabled docker             # "enabled": starts with the server
  ```

- **Undo:** `sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`
  (data in `/var/lib/docker` stays until you delete it).
- If the official instructions changed since this was written, follow
  [docs.docker.com/engine/install](https://docs.docker.com/engine/install/): the result must be the
  same three checks.

### Using Docker without sudo

```bash
sudo usermod -aG docker deploy      # then log out and in again
docker ps                           # works without sudo
```

Being in the `docker` group is **equivalent to root** (a container can mount the whole disk). On a
server only you administer that's the usual trade-off; on a shared one, give it only to admins.

### Log rotation

By default Docker keeps container logs forever and they can fill the disk. Limit them **before**
creating containers (the setting applies to containers created afterwards):

```bash
sudo nano /etc/docker/daemon.json
```

```json
{
  "log-driver": "local",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
```

```bash
sudo systemctl restart docker      # fine now: nothing is running yet
docker info --format '{{.LoggingDriver}}'
```

- **Check:** prints `local`.
- On a server **already running containers**, restarting Docker stops and starts all of them:
  do it at a quiet hour, and know that existing containers keep their old setting until recreated.

## 11 · Folders and the shared network

The guide's model: projects in `/srv/apps/<project>`, the proxy in `/srv/nginx-proxy`, one shared
Docker network.

```bash
sudo mkdir -p /srv/apps /srv/nginx-proxy
sudo chown deploy:deploy /srv/apps /srv/nginx-proxy
docker network create proxy-network
```

- **Check:** `ls -ld /srv/apps /srv/nginx-proxy` shows `deploy` as owner; `docker network ls` lists
  `proxy-network`.
- **Undo:** `docker network rm proxy-network` (only while nothing uses it), `sudo rmdir` the folders.

## 12 · Before moving on

- [ ] A snapshot of the server in the provider's panel, now that it's clean and configured.
- [ ] A short note (in your password manager or private notes, not in a repo): IP, provider, user,
  where the SSH key is, what you configured.
- [ ] From your computer, `nmap -Pn 203.0.113.10` (or an online port scanner) shows only 22, 80, 443
  (80/443 may show "closed" until nginx exists).

Next: [17 · The shared proxy from scratch](17-shared-proxy-from-scratch.md).
