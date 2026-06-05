# Dev Server Walkthrough

This repo builds a combined Hetzner VPS: public HTTPS for one-user Nexus, and
Tailscale-only SSH for Cursor Remote SSH, GitHub SSH, Docker, Codex, and Claude
Code.

The setup is:

```text
Internet -> HTTPS -> dev-server/Caddy -> Nexus
Mac/phone -> Tailscale -> dev-server -> tmux/Cursor/Codex/Claude/Docker/GitHub SSH
```

The normal workflow is the single local script:

```bash
./devbox up
```

It renders cloud-init, converges Hetzner firewall rules, creates or reuses the
server, writes a managed SSH include file, waits for cloud-init, switches SSH to
the Tailscale IP, and removes temporary public SSH.

## 1. Local Prereqs

Install local tools on the Mac:

```bash
brew install hcloud gh
```

For a matching local shell/dev stack, this machine uses:

```bash
brew install atuin eza git-delta lazygit yazi mise direnv fd bat
```

`zoxide`, `fzf`, and `ripgrep` are also part of the local shell/dev stack; the
current Mac setup already had them installed.

Install and sign into the Tailscale Mac app:

```text
https://tailscale.com/download
```

Log into GitHub CLI:

```bash
gh auth login
gh auth status
```

Configure the Hetzner context that owns the dev box:

```bash
hcloud context create dev-infra
hcloud context use dev-infra
hcloud context active
```

Upload your Mac SSH key to Hetzner if needed:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -C "$(whoami)@$(hostname)-macbook"
hcloud ssh-key create \
  --name niels-macbook \
  --public-key-from-file ~/.ssh/id_ed25519.pub
```

If the key already exists, the create command can fail with a duplicate-name
error. Check with:

```bash
hcloud ssh-key list
```

## 2. Repo Secrets

Create the dedicated GitHub SSH key for the server if it does not already exist:

```bash
mkdir -p secrets
chmod 700 secrets
ssh-keygen -t ed25519 \
  -C "niels-dev-server-github" \
  -f secrets/id_ed25519_github \
  -N ""
chmod 600 secrets/id_ed25519_github
chmod 644 secrets/id_ed25519_github.pub
```

Add the public key to GitHub:

```bash
gh ssh-key add secrets/id_ed25519_github.pub \
  --title dev-server \
  --type authentication
```

Create a short-lived, non-ephemeral Tailscale auth key in the Tailscale admin
console. Save it locally:

```bash
printf '%s' 'tskey-auth-...' > secrets/tailscale-auth-key
chmod 600 secrets/tailscale-auth-key
```

The key is injected into generated cloud-init, used once during first boot, and
then removed from the server. The generated `cloud-init-devbox.yaml` remains a
secret file and is ignored by git.

## 3. One-Shot Create Or Update

Run:

```bash
./devbox up
```

What it does:

- Uses Hetzner context `dev-infra`.
- Renders `cloud-init-devbox.yaml`.
- Ensures firewall `dev-server-private` exists.
- Ensures inbound UDP `41641`, TCP `80`, TCP `443`, and temporary TCP `22` from
  your current public `/32`.
- Creates `dev-server` as `cpx21` in Hillsboro if missing.
- Writes `~/.ssh/config.d/dev-server` and ensures `~/.ssh/config` includes that
  directory.
- Waits for SSH and cloud-init.
- Waits for the Tailscale IP.
- Rewrites the `dev-server` SSH alias to the Tailscale IP.
- Runs lockdown and deletes the temporary public SSH firewall rule.

After it finishes:

```bash
ssh dev-server
tmux new -A -s main
```

The first login shell has Powerlevel10k, fzf/fzf-tab, zoxide, atuin, mise,
direnv, eza aliases, delta Git diffs, lazygit, yazi, fd, bat, ripgrep, Docker,
GitHub CLI, Codex, and Claude Code.

## 4. Daily Commands

Check local and live state:

```bash
./devbox doctor
```

Re-run public SSH lockdown:

```bash
./devbox lockdown
```

Render cloud-init without touching Hetzner:

```bash
./devbox render
```

Rebuild from scratch:

```bash
DEVBOX_CONFIRM_REBUILD=dev-server ./devbox rebuild
```

Or run `./devbox rebuild` and type `dev-server` at the confirmation prompt.

## 5. Post-Provision Human Auth

Cloud-init cannot complete browser/device auth for user tools. After a fresh
rebuild, log into:

```text
gh
Codex personal/work
Claude Code personal/work
```

AI tool state is routed by folder:

```text
~/src/work/...      -> work
everything else    -> personal
```

Useful checks:

```bash
ai-whoami
codex-home
claude-home
```

## 6. Console Password

Cloud-init cannot set an interactive password. Set one for the Hetzner web VNC
console after first boot:

```bash
ssh dev-server
sudo passwd niels
```

SSH password auth stays disabled; this password is only for the serial/VNC
console.

## 7. Clean Rebuild Policy

For this small combined Nexus/dev box, prefer clean rebuilds over copying the old
home directory. Clone repos fresh, restore only required env files and secrets,
and re-authenticate tools.

Do not migrate Codex/Claude histories, Cursor server state, Docker build cache,
language package caches, or old `node_modules` trees unless you intentionally
want that state.
