# Dev Server

Personal machine bootstrap for a disposable Hetzner dev box and local
workstations.

The goal is fast, malleable coding machines, not a compliance framework. Remote
boxes are expected to be rebuilt when they drift too far. Local machines use
their native package managers and shared repo-owned dotfiles.

## Files

- `devbox`: create, rebuild, converge, lock down, render, and doctor the
  Hetzner dev box.
- `workstation`: converge, doctor, and install packages/dotfiles/AI tools on a
  local macOS or Arch machine.
- `lib/`: shared shell libraries for logging, doctors, dotfiles, AI tools, and
  platform package commands.
- `assets/`: managed routers and dotfiles.
- `packages/`: native package manifests for Homebrew and Arch.
- `cloud-init-devbox.template.yaml`: first-boot bootstrap for SSH, Tailscale,
  and the temporary host firewall.
- `ansible/`: Ubuntu system setup for the remote dev box.

## One Command

Create a short-lived, reusable, non-ephemeral Tailscale auth key and either export
it or place it in `secrets/tailscale-auth-key`:

```sh
mkdir -p secrets
chmod 700 secrets
printf '%s' 'tskey-auth-...' > secrets/tailscale-auth-key
chmod 600 secrets/tailscale-auth-key
```

Then run:

```sh
./devbox up
```

`up` renders cloud-init to a temporary file, creates or reuses the Hetzner VPS,
waits for Tailscale, rewrites the SSH alias to the Tailscale IP, runs lockdown,
runs Ansible, and runs a lightweight doctor.

## Daily Commands

```sh
./devbox doctor
./devbox converge
./devbox lockdown
DEVBOX_CONFIRM_REBUILD=dev-server ./devbox rebuild
DEVBOX_RENDER_OUTPUT=cloud-init-devbox.yaml ./devbox render
```

Local workstation commands:

```sh
./workstation doctor
./workstation converge
./workstation packages
./workstation dotfiles
./workstation ai-tools
```

## Guardrails

- Public SSH is temporary. After Tailscale is up, `lockdown` removes host and
  Hetzner SSH ingress.
- Public HTTP/HTTPS is managed by `up` and `lockdown`; set
  `DEVBOX_PUBLIC_WEB=1` before running them to open it.
- `converge` installs and updates the desired packages, services, shell config,
  and AI-tool shortcuts. It does not clean unrelated drift; rebuild or clean the
  box manually when that is what you want.
- `doctor` checks the health of required pieces. It does not audit for the
  absence of unrelated state.
- Local workstation packages are native: Homebrew on macOS, pacman plus an
  explicit AUR list on Arch.
- AI tool shortcuts are shared across platforms. `~/bin/codex`,
  `~/bin/codex-personal`, `~/bin/codex-work`, `~/bin/claude`,
  `~/bin/claude-personal`, and `~/bin/claude-work` all point at one managed
  router under `~/.local/libexec/ai-router`.
- Generated cloud-init is secret-bearing. Normal commands use temporary files;
  keep `cloud-init-devbox.yaml` out of git.
- The `secrets/` directory is ignored and should stay local.

## Docker

Rootless Docker is the configured default. `./devbox converge` installs the
rootless service, log policy, and shell environment. Do not keep long-lived
state only in Docker on this box.

## Philosophy

This is a one-user prototype machine. Prefer small shell and Ansible that are easy
to read and edit. Rebuild instead of carrying migration machinery. Add heavier
systems only when the box has a real repeated failure mode.
