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

Arch convergence installs Mosh and Tailscale, enables `tailscaled`, and leaves
the one-time tailnet login to
`sudo tailscale up --operator="$(id -un)"`. macOS convergence installs Mosh,
reuses an existing Tailscale app or installs the recommended standalone app
when missing, and leaves its one-time system-extension approval and login to
the app.

On the Huawei MACH-WX9, workstation convergence installs a device-matched
libinput preset for the `SYNA1D31` touchpad. It uses a custom curve with
low/medium/moderately-fast/fast motion gains of approximately
`1.0x`/`8.0x`/`9.0x`/`15.0x`, natural two-finger scrolling, clickfinger
buttons, tap-to-click, and disable-while-typing. The custom profile affects
pointer motion only. It is applied immediately under X11 and stored under
`/etc/X11/xorg.conf.d/` for subsequent sessions.

On EndeavourOS, workstation convergence also installs an LTS fallback kernel,
an 8 GiB zram policy, firmware and NVMe tooling, shell linters, and package
maintenance tools. It removes the installer onboarding applications and stale
Electron runtimes, disables public-zone SSH access, enables weekly mirror
refreshes using health-ranked US and Canadian mirrors, configures `eos-update`
to include AUR updates through `yay`, and keeps local-NVMe dracut images free
of unneeded network storage modules. The normal Arch kernel remains the
systemd-boot default while LTS stays available as a fallback.

Firmware metadata, SMART disk health, package-file indexes, and package-cache
cleanup run automatically. XFCE also gets persistent searchable clipboard
history on `Super+V` and a Los Angeles solar schedule for Gammastep night color.

Arch convergence installs Cursor from the explicit AUR manifest and adds
Anysphere's Remote SSH extension. The `dev-server` and `macbook` aliases are
preclassified as Linux and macOS remotes. A remote repository can be opened
directly from a shell with a folder URI:

```sh
cursor --folder-uri 'vscode-remote://ssh-remote+dev-server/home/niels/src/personal/dev-server'
cursor --folder-uri 'vscode-remote://ssh-remote+macbook/Users/nnandal/Documents/code/dev-server'
```

Arch convergence also installs Ghostty from the official repositories and
makes it XFCE's preferred terminal while retaining XFCE Terminal as a fallback.
The managed Ghostty profile uses the existing Meslo Nerd Font, dark native UI,
automatic zsh integration, five-minute background reuse, and desktop
notifications for commands that finish after 30 seconds while unfocused.

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
  managed router under `~/.local/libexec/ai-router` for separate account state.
  OpenCode uses the direct `~/bin/opencode` shortcut and its native state
  locations; it does not pretend to provide isolated contexts.
- Generated cloud-init is secret-bearing. Normal commands use temporary files;
  keep `cloud-init-devbox.yaml` out of git.
- The `secrets/` directory is ignored and should stay local.

## Codex account shortcuts

Convergence installs one Codex binary with three isolated account homes:

- `codex-personal` uses `~/.codex-personal`.
- `codex-work` uses `~/.codex-work`.
- `codex-work2` uses `~/.codex-work2`.

Plain `codex` continues to select personal or work state from the target path.
The second work account is explicit-only and is never selected by path. Each
home is a complete `CODEX_HOME`, so authentication, configuration, sessions,
skills, plugins, logs, and other Codex state remain separate.

Credentials are intentionally not provisioned. After the first convergence on
a local machine, authenticate the new ChatGPT subscription in a private browser
session so an existing account is not selected accidentally:

```sh
codex-work2 login
codex-work2 login status
```

On the headless dev box, first enable device-code login in the new account's
ChatGPT security settings, then enroll that machine separately:

```sh
ssh dev-server
codex-work2 login --device-auth
codex-work2 login status
```

`login status` confirms the authentication method, not the account identity.
Verify the new account in the browser flow. Use ChatGPT login for subscription
access; API-key login is usage-billed separately. Never put `auth.json`, access
tokens, or device codes in this repo, Ansible, shell startup files, or chat.

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

The Arch workstation uses the distribution Docker service. Convergence enables
it and adds the workstation user to the `docker` group, which grants
root-equivalent access. Log out and back in before first use. If a full system
upgrade replaced the running kernel, convergence leaves Docker enabled, reports
a doctor warning, and waits for the required reboot instead of aborting the rest
of workstation setup.

## Philosophy

This is a one-user prototype machine. Prefer small shell and Ansible that are easy
to read and edit. Destructive server replacement is intentionally manual because
server identity and pricing can matter. Add heavier systems only when the box has
a real repeated failure mode.
