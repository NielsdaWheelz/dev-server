# Dev Server

This directory contains the Hetzner bootstrap for the `dev-server` remote
development VPS.

For the full from-scratch setup, see [WALKTHROUGH.md](WALKTHROUGH.md).

## Files

- `cloud-init-devbox.template.yaml`: non-secret source template. Edit this file
  when changing the server bootstrap.
- `bash_aliases`: shell helpers injected into the server. This is the source of
  truth for directory-aware Codex/Claude account routing.
- `zshrc`: managed Zsh config injected into the server. Enables zoxide `z`,
  fzf key bindings, fzf-tab completions, autosuggestions, syntax highlighting,
  `~/bin` command wrappers, and a lightweight colored prompt.
- `secrets/id_ed25519_github`: dedicated GitHub SSH private key for this dev
  server. Keep this private.
- `secrets/id_ed25519_github.pub`: matching public key, already added to GitHub.
- `render-cloud-init.sh`: renders the final cloud-init file by injecting the
  GitHub SSH key, `bash_aliases`, and `zshrc`.
- `cloud-init-devbox.yaml`: generated cloud-init user-data passed to `hcloud`.
  Treat this as secret because it contains the GitHub private key.

## Render

```bash
/Users/nnandal/Documents/code/dev-server/render-cloud-init.sh
```

## Create Server

Baseline server type is `cpx31` (4 vCPU / 8 GB RAM). We moved up from `cpx11`
(2 GB) after a memory-OOM wedged the box and we had to rebuild. The extra
headroom is for concurrent Codex/Claude/Docker workloads.

```bash
hcloud server create \
  --name dev-server \
  --type cpx31 \
  --image ubuntu-24.04 \
  --location hil \
  --ssh-key niels-macbook \
  --firewall dev-server-private \
  --enable-backup \
  --label purpose=remote-dev \
  --label environment=dev \
  --user-data-from-file /Users/nnandal/Documents/code/dev-server/cloud-init-devbox.yaml
```

After a fresh rebuild, re-run human auth for `gh`, Codex personal/work,
Claude Code personal/work, and Tailscale.

## Dev Box Defaults

These are the post-OOM-incident defaults baked into the cloud-init template.
If you change one of these, update the section below so future rebuilds match.

- Server type: `cpx31` (8 GB RAM) — see "Create Server" above.
- Persistent journald with `SystemMaxUse=1G`: drop-in at
  `/etc/systemd/journald.conf.d/00-devbox-persistent.conf` plus `mkdir -p
  /var/log/journal` in `devbox-bootstrap.sh`. Lets us post-mortem OOMs after
  reboot with `journalctl -b -1`.
- `earlyoom` installed and enabled: kills the fattest process before the
  kernel OOM-killer wedges the whole VM.
- No swapfile. With 8 GB RAM and `earlyoom` we want the worst process killed,
  not paged out — swap was what turned the last OOM into a thrash-wedge.
- Docker daemon log rotation: `/etc/docker/daemon.json` caps container logs
  at 50 MB x 3 files so a chatty container can't fill the disk.
- Final public ingress posture: Hetzner Cloud Firewall `dev-server-private`
  permits Tailscale direct WireGuard UDP `41641` from the internet and no
  public TCP ports. Host UFW allows inbound traffic on `tailscale0` only after
  `/usr/local/sbin/devbox-lockdown-public-ssh.sh` runs.
- Bootstrap SSH is temporary: first boot allows SSH only from the operator's
  current public `/32` at the Hetzner edge and `22/tcp` in UFW. After Tailscale
  enrollment, remove the Hetzner SSH rule and run the lock-down script.
- tmux session persistence: `tpm` cloned to `~/.tmux/plugins/tpm`, with
  `tmux-resurrect` + `tmux-continuum` enabled in `~/.tmux.conf`. Sessions
  auto-restore after reboot.
- Extra CLI tools: `htop ncdu ripgrep fd-find bat jq` are in the apt install
  list in `devbox-bootstrap.sh`.
- Codex uses two explicit homes: `~/.codex-personal` and `~/.codex-work`.
  `~/.codex` is created as a compatibility symlink to personal, and `~/bin`
  wrappers route plain `codex` calls by directory so raw executable launches do
  not create a third state store.

### Post-Provision Manual Step

Cloud-init can't set an interactive password. After the server is up, set a
console password for `niels` so the Hetzner VNC console works as a fallback
when SSH is dead:

```bash
ssh dev-server
sudo passwd niels
```

Pick something strong and store it in your password manager. SSH password
auth stays disabled (`PasswordAuthentication no` in
`/etc/ssh/sshd_config.d/99-devbox.conf`); this password is only used at the
serial/VNC console.

## Git Safety

The repo tracks the template and renderer, not the rendered cloud-init file or
private SSH key. Keep `cloud-init-devbox.yaml` and `secrets/` out of git unless
they are encrypted first.
