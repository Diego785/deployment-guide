# 08 · DNS

DNS translates `app.example.com` into the server's IP. Without it, nobody (including Let's
Encrypt) finds your app by name.

## What to create

In the DNS panel of whoever manages the domain (registrar, Cloudflare, the hosting provider…):

| Type | Name | Value | TTL |
| --- | --- | --- | --- |
| `A` | `app` | `203.0.113.10` | 300 (5 min) or "Auto" |

- **Name** is only the part before the domain: `app` creates `app.example.com`. `@` means the bare
  domain (`example.com`); `www` creates `www.example.com`.
- **A** points to an IPv4 address. **AAAA** is for IPv6: create it only if the server has IPv6
  **and** nginx listens on it; a wrong AAAA record breaks access for IPv6 users and can make
  certificate validation fail.
- **CNAME** points a name to another name (`www` → `example.com`). It can't be used on the bare
  domain.
- A low TTL (300) while you set things up lets you correct mistakes fast; raise it later if you
  want.

### What to ask for, if someone else manages DNS

> Please create an **A record** `app.example.com` → `203.0.113.10` (TTL 300). If it's on
> Cloudflare, leave it **"DNS only"** (grey cloud) until the certificate is issued.

### Cloudflare's proxy (orange cloud)

With the orange cloud, traffic goes through Cloudflare and visitors see Cloudflare's IP. It
works, but:

- Leave it grey while you get the Let's Encrypt certificate (or use Cloudflare's own origin
  certificates).
- Set SSL/TLS mode to **Full (strict)** once your server has a valid certificate; "Flexible" causes
  redirect loops with the phase 2 config.

## Checking it

```bash
nslookup app.example.com              # Windows, macOS, Linux
dig +short app.example.com            # Linux/macOS
nslookup app.example.com 1.1.1.1      # ask a specific public resolver, skipping your cache
```

The answer must be the server's IP. Online, sites like dnschecker.org show it from many
countries.

- **Right after creating it**, some resolvers still answer "doesn't exist" for a while (they cached
  the negative answer). Usually minutes; rarely a few hours.
- **Changing an existing record** takes up to the old TTL to be seen everywhere.

## Order of operations

DNS can be done at any time, but certificates need it. A good order:

1. Deploy the app and test it without a domain ([09](09-without-a-domain.md)).
2. Create the DNS record (or ask for it).
3. When `nslookup` returns the IP: phase 1 nginx → certificate → phase 2.

You can have phase 1 loaded before DNS exists: it does no harm and lets you test with a `hosts`
entry ([09](09-without-a-domain.md)).
