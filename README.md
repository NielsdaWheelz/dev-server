# Dev Server

One-command provisioner for a disposable single-user Hetzner dev box.

The goal is a fast, malleable coding machine, not a compliance framework. The box
is expected to be rebuilt when it drifts too far.

## Files

- `devbox`: create, rebuild, converge, lock down, render, and doctor.
- `cloud-init-devbox.template.yaml`: first-boot bootstrap for SSH, Tailscale,
  and the temporary host firewall.
- `ansible/`: ongoing package, shell, AI-tool, security, and Docker setup.
- `zshrc`, `zsh_helpers`, `p10k.zsh`: managed shell environment.

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
