# Dev Server

This directory contains the Hetzner bootstrap for the combined `dev-server`
remote development and one-user Nexus VPS.

For the full from-scratch setup, see [WALKTHROUGH.md](WALKTHROUGH.md).

## Files

- `devbox`: the one local entrypoint. Use `./devbox up`, `./devbox lockdown`,
  `./devbox doctor`, `./devbox rebuild`, and `./devbox render`.
- `cloud-init-devbox.template.yaml`: non-secret source template. Edit this file
  when changing the server bootstrap.
- `zsh_helpers`: Zsh helpers injected into the server as
  `/home/niels/.zsh_helpers`. This is the source of truth for
  directory-aware Codex/Claude account routing.
- `zshrc`: managed Zsh config injected into the server. Enables zoxide `z`,
  fzf key bindings, fzf-tab completions, `mise`, `direnv`, `atuin`,
  autosuggestions, syntax highlighting, Powerlevel10k, and `~/bin` command
  wrappers.
- `p10k.zsh`: managed Powerlevel10k prompt config injected into the server as
  `/home/niels/.p10k.zsh`.
- `secrets/id_ed25519_github`: dedicated GitHub SSH private key for this dev
  server. Keep this private.
- `secrets/id_ed25519_github.pub`: matching public key, already added to GitHub.
- `secrets/tailscale-auth-key`: short-lived Tailscale auth key for one-shot
  first-boot enrollment. Required by `./devbox up` unless
  `DEVBOX_TAILSCALE_AUTH_KEY` is set. Keep this private.
- `cloud-init-devbox.yaml`: generated cloud-init user-data passed to `hcloud`.
  Treat this as secret because it contains the GitHub private key and, when
  present, the Tailscale auth key.

## One-Shot Up

Create a short-lived, non-ephemeral Tailscale auth key and save it locally:

```bash
mkdir -p secrets
chmod 700 secrets
printf '%s' 'tskey-auth-...' > secrets/tailscale-auth-key
chmod 600 secrets/tailscale-auth-key
```

Then run:

```bash
./devbox up
```

`./devbox up` renders cloud-init, converges the Hetzner firewall, creates or
reuses the server, writes `~/.ssh/config.d/dev-server`, waits for cloud-init,
switches the `dev-server` SSH alias to the Tailscale IP, and locks down public
SSH. It leaves a `dev-server-public` SSH alias in the include file for explicit
public-path checks.

Useful commands:

```bash
./devbox doctor
./devbox lockdown
DEVBOX_CONFIRM_REBUILD=dev-server ./devbox rebuild
./devbox render
```

After a fresh rebuild, re-run human auth for `gh`, Codex personal/work, and
Claude Code personal/work. Clone repos fresh, restore only required env files
and secrets, and do not migrate Codex/Claude histories, Cursor server state,
Docker build cache, language package caches, or old `node_modules` trees unless
you intentionally want that state.

## Dev Box Defaults

These are the current cost-conscious defaults baked into the cloud-init template.
If you change one of these, update the section below so future rebuilds match.

- Server type: `cpx21` in Hillsboro (3 shared vCPU / 4 GB RAM / 80 GB disk /
  2 TiB traffic, $13.99/mo before tax) — see "One-Shot Up" above.
- Hetzner backups are not enabled in the create command. Enable them manually if
  the extra 20% monthly cost is worth it for a given rebuild. On `cpx21`, that
  would add about $2.80/mo.
- Persistent journald with `SystemMaxUse=512M`: drop-in at
  `/etc/systemd/journald.conf.d/00-devbox-persistent.conf` plus `mkdir -p
  /var/log/journal` in `devbox-bootstrap.sh`. Lets us post-mortem OOMs after
  reboot with `journalctl -b -1` without crowding the smaller disk.
- `earlyoom` installed and enabled with preferences for killing agent/dev
  processes (`node`, `codex`, `claude`, `cursor-server`, `python`, etc.) before
  core services.
- A 4 GB swapfile is created with `vm.swappiness=20`. Swap absorbs short
  agent/build bursts on the 4 GB box; `earlyoom` still protects the system from
  wedging.
- Docker daemon log rotation: `/etc/docker/daemon.json` caps container logs
  at 20 MB x 3 files so a chatty container can't fill the disk.
- Final public ingress posture: Hetzner Cloud Firewall `dev-server-private`
  permits Tailscale direct WireGuard UDP `41641` plus public TCP `80`/`443` for
  Caddy. Host UFW keeps `80`/`443` public and allows admin traffic on
  `tailscale0` after `/usr/local/sbin/devbox-lockdown-public-ssh.sh` runs.
- Bootstrap SSH is temporary: first boot allows SSH only from the operator's
  current public `/32` at the Hetzner edge and `22/tcp` in UFW. After Tailscale
  enrollment, remove the Hetzner SSH rule and run the lock-down script.
- tmux session persistence: `tpm` cloned to `~/.tmux/plugins/tpm`, with
  `tmux-resurrect` + `tmux-continuum` enabled in `~/.tmux.conf`. Sessions
  auto-restore after reboot.
- Extra CLI tools: apt installs the baseline system tools (`htop`, `ncdu`,
  `ripgrep`, `fd-find`, `bat`, `jq`, `direnv`) and creates normal `fd`/`bat`
  command names. `mise` is installed as `niels` and then installs `atuin`,
  `eza`, `delta`, `lazygit`, and `yazi` into `~/.local/share/mise`.
- Git is configured for `niels` to use `delta` as the pager and interactive
  diff filter, with `zdiff3` conflict markers.
- The managed `~/.zshrc` is a curated Ubuntu remote-dev shell, not a copy of the
  Mac `~/.zshrc`. It includes PATH setup, history, fzf, fzf-tab, zoxide,
  `mise`, `direnv`, `atuin`, direct Zsh completion setup, Powerlevel10k,
  autosuggestions, syntax highlighting, and the AI account routing helpers. It
  intentionally omits Mac-only Homebrew paths, Android SDK, Homebrew Java setup,
  and project-specific language/runtime tools.
- Codex, Claude Code, and Corepack shims are installed as `niels` under
  `~/.local/bin` via npm's user-local prefix, not as root-owned global npm
  packages.
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

The repo tracks the template and `devbox` entrypoint, not the rendered
cloud-init file or private SSH key. Keep `cloud-init-devbox.yaml` and `secrets/`
out of git unless they are encrypted first.
