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
waits for Tailscale, rewrites the SSH alias to the Tailscale IP, removes public
SSH, runs Ansible, and runs a lightweight doctor.

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
- Public HTTP/HTTPS is closed unless `DEVBOX_PUBLIC_WEB=1` is set.
- Hetzner paid backups are intentionally not used. `doctor` fails if a Hetzner
  `BackupWindow` is present.
- Generated cloud-init is secret-bearing. Normal commands use temporary files;
  keep `cloud-init-devbox.yaml` out of git.
- The `secrets/` directory is ignored and should stay local.

## Docker

Rootless Docker is the only supported Docker posture. `./devbox converge`
stops rootful Docker and system containerd, removes their state, and enables the
user's rootless Docker service. Do not keep long-lived state only in Docker on
this box.

## Philosophy

This is a one-user prototype machine. Prefer small shell and Ansible that are easy
to read and edit. Rebuild instead of carrying migration machinery. Add heavier
systems only when the box has a real repeated failure mode.
