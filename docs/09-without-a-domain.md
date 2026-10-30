# 09 · Seeing the app without a domain

The app is running on the server, but the domain doesn't point there yet (or you don't want to
expose it yet). Three ways to see it, from safest to least safe.

## Option 1 · SSH tunnel (recommended)

Nothing opens to the internet. Only you, with the tunnel up, see the app at `localhost`.

1. Find the container's IP on the shared network (on the server):

   ```bash
   docker inspect my-app --format '{{range $n, $c := .NetworkSettings.Networks}}{{$n}} {{$c.IPAddress}}{{println}}{{end}}'
   ```

   You get something like `proxy-network 172.18.0.7`.

2. On **your computer**, open the tunnel (keep this terminal open):

   ```bash
   ssh -N -L 8080:172.18.0.7:3000 root@203.0.113.10
   ```

3. Open `http://localhost:8080` in your browser.

Notes:

- The container's IP can change when it's recreated; repeat step 1 if the tunnel stops working.
- Apps that redirect to their `APP_URL` (logins, OAuth) may send you to the real domain. For a quick
  test, temporarily set `APP_URL=http://localhost:8080` in `.env` and `docker compose up -d app`;
  set it back afterwards.
- Secure cookies (`Secure`) aren't sent over plain HTTP, except that browsers treat `localhost` as
  secure, so logins usually work through the tunnel.

## Option 2 · `hosts` file (tests nginx too)

Your computer believes the domain points to the server, before the real DNS does. It tests the
whole chain: nginx, `server_name`, proxy and app. HTTP only (phase 1): there's no certificate yet.

1. Load the phase 1 `.conf` on the server (`nginx -t`, reload). It's harmless without DNS.
2. On your computer, add a line to the hosts file:
   - Windows: `C:\Windows\System32\drivers\etc\hosts` (open Notepad **as administrator**)
   - macOS/Linux: `/etc/hosts` (`sudo nano /etc/hosts`)

   ```text
   203.0.113.10   app.example.com
   ```

3. Open `http://app.example.com` (if the browser forces `https`, type `http://` explicitly or use a
   private window).
4. **Remove the line when you're done**, or you'll keep seeing the server even after the real DNS
   changes. On Windows, `ipconfig /flushdns` clears the cache.

Anyone else can do the same, so it's also a way to show it to a colleague.

## Option 3 · Temporarily publish a port (least safe)

Anyone who knows the IP and port can see it, over plain HTTP. Use it only for a short demo, for
something with no real data, and remove it afterwards.

```yaml
# docker-compose.yml, service app, temporarily:
    ports:
      - "3400:3000"        # server port 3400 → container port 3000
```

```bash
docker compose up -d app
# open http://203.0.113.10:3400
```

Before choosing a port, check it's free: `ss -tln | grep ':3400 '` must print nothing. Remove the
`ports:` lines and run `docker compose up -d app` again when you're done.

A variant that doesn't open anything to the internet: `"127.0.0.1:3400:3000"` publishes only on the
server's loopback, and you reach it with a tunnel (`ssh -N -L 3400:127.0.0.1:3400 my-server`). It's
option 1 with a stable address.

## Which one?

| Need | Option |
| --- | --- |
| I want to check the app works | 1 · tunnel |
| I want to check nginx + app before DNS | 2 · hosts |
| A client must see it today with no domain | 3, for the time of the demo, or better: get the DNS record |
