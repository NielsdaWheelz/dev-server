# Dev Server

Personal machine bootstrap for a disposable Hetzner dev box and local
workstations.

The goal is fast, malleable coding machines, not a compliance framework. Remote
boxes are converged in place. Local machines use their native package managers
and shared repo-owned dotfiles.

## Files

- `devbox`: converge and doctor the Hetzner dev box.
- `workstation`: converge and doctor a local macOS or Arch machine.
- `lib/`: shared shell libraries for logging, doctors, dotfiles, AI tools, and
  platform package commands.
- `assets/`: managed routers and dotfiles.
- `packages/`: native package manifests for Homebrew and Arch.
- `cloud-init-devbox.template.yaml`: first-boot bootstrap for SSH, Tailscale,
  and the temporary host firewall.
- `ansible/`: Ubuntu system setup for the remote dev box.

## One Command

Create a short-lived, reusable, non-ephemeral Tailscale auth key and place it in
`secrets/tailscale-auth-key`:

```sh
mkdir -p secrets
chmod 700 secrets
printf '%s' 'tskey-auth-...' > secrets/tailscale-auth-key
chmod 600 secrets/tailscale-auth-key
```

Then run:

```sh
./devbox converge
```

`converge` creates the Hetzner VPS if it is missing, reuses it when it already
exists, waits for Tailscale, rewrites the SSH alias to the Tailscale IP, locks
down public SSH, runs Ansible, and runs a lightweight doctor.

## Daily Commands

```sh
./devbox converge
./devbox doctor
```

Local workstation commands:

```sh
./workstation converge
./workstation doctor
```

## Guardrails

- Public SSH is temporary. After Tailscale is up, `converge` removes host and
  Hetzner SSH ingress.
- `converge` installs and updates the desired packages, services, shell config,
  and AI-tool shortcuts. It does not clean unrelated drift or delete/recreate
  the server.
- `doctor` checks the health of required pieces. It does not audit for the
  absence of unrelated state.
- Local workstation packages are native: Homebrew on macOS, pacman plus an
  explicit AUR list on Arch.
- AI tool shortcuts are shared across platforms. Codex and Claude use the
  managed router under `~/.local/libexec/ai-router` for separate personal and
  work state. OpenCode uses the direct `~/bin/opencode` shortcut and its native
  state locations; it does not pretend to provide isolated contexts.
- Generated cloud-init is secret-bearing. Normal commands use temporary files;
  keep `cloud-init-devbox.yaml` out of git.
- The `secrets/` directory is ignored and should stay local.

## OpenCode with Kimi K3

Convergence installs OpenCode, makes `kimi-for-coding/k3` the default model at
max reasoning effort, disables session sharing and self-updates, and installs a
guarded permission policy without weakening OpenCode's read-only Plan and
Explore agents. Build stays fluid inside the current workspace, while direct
reads and edits of environment credentials and `secrets/` paths are blocked;
`.env.example` remains usable. Every shell command requires approval, including
commands launched by OpenCode's built-in agents. On the Ubuntu dev box, the
guardrail policy is also installed under `/etc/opencode/` at OpenCode's
highest-precedence managed tier. Workstations receive the same policy as a
user-wide default.

Treat the permission policy as an interactive guardrail, not a process
sandbox. Review project-local OpenCode config and custom agents before using an
untrusted repository, and do not use `opencode --auto` there: auto mode approves
actions which would otherwise prompt.

The managed model limit is the conservative 256K context available with a
Moderato membership. Kimi advertises up to 1M only for Allegretto and higher;
raise `provider.kimi-for-coding.models.k3.limit.context` to `1048576` in the
`assets/opencode/opencode.json` asset if the subscription is upgraded.

The Kimi Code credential is intentionally not provisioned. Kimi Code membership
keys and Kimi Open Platform keys use different services and are not
interchangeable. After convergence, enroll a Kimi Code key interactively:

```sh
ssh dev-server
opencode auth login --provider kimi-for-coding
opencode auth list
opencode models kimi-for-coding
opencode
```

Create the key in the [Kimi Code Console](https://www.kimi.com/code/console),
paste it only into OpenCode's credential prompt, and select **Kimi For Coding**
if OpenCode asks for a provider. The credential stays in OpenCode's user data;
do not put it in this repo, Ansible variables, shell startup files, or
screenshots.

The first production check should use a fresh session. Confirm the status bar
shows Kimi K3 and `max`, exercise a read/edit/shell tool loop, reject and approve
a permission prompt, then resume the session with `opencode --continue`. Also
exercise compaction on a long session before relying on K3 for unattended work.

## Docker

Rootless Docker is the configured default. `./devbox converge` installs the
rootless service, log policy, and shell environment. Do not keep long-lived
state only in Docker on this box.

## Philosophy

This is a one-user prototype machine. Prefer small shell and Ansible that are easy
to read and edit. Destructive server replacement is intentionally manual because
server identity and pricing can matter. Add heavier systems only when the box has
a real repeated failure mode.
