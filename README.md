# Dev Server

This directory contains the Hetzner bootstrap for the `dev-server` remote
development VPS.

## Files

- `cloud-init-devbox.template.yaml`: non-secret source template. Edit this file
  when changing the server bootstrap.
- `secrets/id_ed25519_github`: dedicated GitHub SSH private key for this dev
  server. Keep this private.
- `secrets/id_ed25519_github.pub`: matching public key, already added to GitHub.
- `render-cloud-init.sh`: renders the final cloud-init file by injecting the
  GitHub SSH key.
- `cloud-init-devbox.yaml`: generated cloud-init user-data passed to `hcloud`.
  Treat this as secret because it contains the GitHub private key.

## Render

```bash
/Users/nnandal/Documents/code/dev-server/render-cloud-init.sh
```

## Create Server

```bash
hcloud server create \
  --name dev-server-cpx11 \
  --type cpx11 \
  --image ubuntu-24.04 \
  --location hil \
  --ssh-key nexus-macbook \
  --firewall dev-trial-ssh \
  --enable-backup \
  --label purpose=remote-dev \
  --label environment=dev \
  --user-data-from-file /Users/nnandal/Documents/code/dev-server/cloud-init-devbox.yaml
```

After a fresh rebuild, re-run human auth for `gh`, Codex, Claude, and Tailscale.

## Git Safety

The repo tracks the template and renderer, not the rendered cloud-init file or
private SSH key. Keep `cloud-init-devbox.yaml` and `secrets/` out of git unless
they are encrypted first.
