# 01 · SSH access

SSH opens a terminal on the server from your computer. Everything else happens inside that
terminal.

## Connecting

```bash
ssh root@203.0.113.10          # user@IP; asks for the password the first time
ssh -p 2222 root@203.0.113.10  # if SSH listens on a port other than 22
```

The first time it asks you to confirm the server's fingerprint (`yes`). If one day it says
**"REMOTE HOST IDENTIFICATION HAS CHANGED"**, stop: either the server was reinstalled or someone is
in the middle. Ask the server's admin before removing the old line from `~/.ssh/known_hosts`.

To leave: `exit` (or `Ctrl+D`).

### On Windows

- `ssh` comes with Windows 10/11 (PowerShell, cmd or Git Bash).
- **Type the password; don't paste it.** Pasting with right-click often adds invisible characters
  and you get `Permission denied`. Nothing shows while you type: that's normal.
- Redirecting input (`ssh … < script.sh`) or wrapping it in `cmd /c` can break the password prompt.
  Connect first, interactively, and run things once inside.

## SSH keys (better than a password)

A key pair: the **private** key stays on your computer (never share it); the **public** one is copied
to the server. Then you log in without typing the password, and nobody can guess it.

```bash
# On your computer, once (Enter to accept the defaults; a passphrase is recommended)
ssh-keygen -t ed25519 -C "my-laptop"

# Copy the public key to the server (Linux/macOS/Git Bash)
ssh-copy-id root@203.0.113.10

# Windows PowerShell has no ssh-copy-id; this does the same thing:
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh root@203.0.113.10 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

On a server that isn't yours, ask before adding keys: the admin may want to know who has access.

## A short name for the server

`~/.ssh/config` on your computer (on Windows: `C:\Users\<you>\.ssh\config`):

```text
Host my-server
    HostName 203.0.113.10
    User root
    # Port 2222
    # IdentityFile ~/.ssh/id_ed25519
```

Now `ssh my-server` is enough, and it also works with `scp` and tunnels.

## Copying files

```bash
# From your computer to the server
scp docker-compose.yml my-server:/srv/apps/my-app/
scp -r ./nginx my-server:/srv/apps/my-app/

# From the server to your computer
scp my-server:/srv/apps/my-app/backups/db-2026-01-31.dump .
```

For text files it's often simpler to open them on the server with an editor
(`nano file`; save `Ctrl+O`, Enter; exit `Ctrl+X`) and paste the content.

## Saving a command's output to show someone

```bash
some-command 2>&1 | tee ~/output.txt   # shows it and also saves it
```

Then copy it with `scp` or select it in the terminal.

## Tunnels: see a private port on your computer

A tunnel brings a server port (or a container's) to `localhost` on your machine, without opening
anything to the internet. Great for viewing an app before DNS exists or a database admin tool.

```bash
# localhost:8080 on your computer → port 3000 at 172.18.0.5 as seen from the server
ssh -N -L 8080:172.18.0.5:3000 my-server
```

`-N` means "don't open a shell, just keep the tunnel". Close it with `Ctrl+C`. Details in
[Seeing the app without a domain](09-without-a-domain.md).

## Good habits on the server

- Before running something, read it. If you don't understand a flag, look it up.
- `pwd` (where am I?) before anything that deletes or overwrites.
- Prefer commands that **show** (`ls`, `cat`, `docker ps`) until you know the place.
- Keep a log of what you ran (`history` shows it, but write the important parts down).
- Don't leave sessions open on shared computers.
