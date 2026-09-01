# Dev Server

One-user convergence for the owned `macbook`, `arch`, and Hetzner `devbox` hosts.
It installs declared state, activates only affected consumers, proves critical
postconditions, and reports mutations, deferrals, or required actions.

The public surface is intentionally complete and small:

```sh
./workstation apply
./devbox apply
./test
```

An omitted or unknown operation exits `64`. Apply exits `0` when declared state
is installed, `2` when a manual action is required, and `1` on an operational or
invariant failure. Rerunning is safe. With fixed native package candidates, an
immediate second apply reports `UP TO DATE` and performs no managed-state
mutation or activation.

The detailed capability contract and acceptance criteria are in [SPEC.md](SPEC.md).
Fleet invitation, acceptance, reboot, and outage workflows live in the
[Skíðblaðnir repository](https://github.com/NielsdaWheelz/skidbladnir).

## Workstation

Prerequisites:

- macOS on the owned MacBook with Homebrew and the App Store Tailscale app
  installed and signed in; or Arch Linux on the exact owned `arch` host with
  `pacman`, `yay`, and interactive sudo elevation for declared machine policy;
- Git, curl, Python 3, tmux, Tailscale, and the platform's standard service
  tools;
- existing GitHub, AI-tool, Tailscale, SSH, and Skíðblaðnir credentials where
  enrollment has already occurred.

Run:

```sh
./workstation apply
```

The order is native packages, repo-owned files, exact-host personal policy,
pinned AI tools, and Skíðblaðnir. Package managers may refresh their own
metadata. Apply never removes Arch packages, restarts tmux, reboots, logs out,
or interrupts running containers. Those cases are reported as `DEFERRED`.
On macOS, apply verifies and may start the exact App Store Tailscale app but
never installs, upgrades, replaces, or signs in to it.

Plain `codex` and `claude` remain upstream personal commands. The only managed
account wrappers are `codex-work`, `codex-work2`, and `claude-work`; authenticate
their isolated homes directly when first required.

## Devbox

Prerequisites:

- authenticated `hcloud` context `dev-infra`, local Tailscale, `gh`, SSH,
  Python 3, and `uvx`;
- operator key `~/.ssh/id_ed25519` and distinct deployment key
  `~/.ssh/dev-server-deploy`, both regular private-key files with mode `0600`;
- `Include ~/.ssh/config.d/*` in the operator's top-level SSH config;
- for a new server only, a short-lived reusable Tailscale auth key in
  `secrets/tailscale-auth-key`, containing exactly one newline-terminated value
  with mode `0600`.

Create the deployment key once if needed:

```sh
ssh-keygen -t ed25519 -f "$HOME/.ssh/dev-server-deploy" -C dev-server-deploy
chmod 0600 "$HOME/.ssh/dev-server-deploy"
install -d -m 0700 secrets
printf '%s\n' 'tskey-auth-...' >secrets/tailscale-auth-key
chmod 0600 secrets/tailscale-auth-key
```

Run:

```sh
./devbox apply
```

When the server is absent, apply creates it, limits temporary public SSH to the
operator's exact IPv4 `/32`, establishes the OpenSSH host key over the tailnet,
and removes bootstrap ingress on success or failure. When it exists, apply uses
only strict tailnet OpenSSH as `dev-server-deploy`; it never opens public SSH or
resets host keys. Ansible owns Ubuntu state. `dev-server` remains the unprivileged
`niels` operator alias.

Missing GitHub enrollment is reported as one exact `ACTION`. Apply does not
mutate GitHub accounts or keys. Controller inputs are validated, copied with
their modes to one immutable per-run stage, and consumed only from that stage.
Rootless Docker's supported unit/context setup is rebuilt only when its
package, generated unit, or daemon config identity changed and no container is
running; otherwise activation is deferred.

## One-time hard cutover

This release does not read, migrate, alias, or fall back to any legacy command,
layout, state file, or release-pin schema. The cut is deliberately irreversible;
preserve credentials and identities, then remove only the exact obsolete paths
below before the first new apply on each host.

### Existing devbox: establish the privilege boundary

Use the Hetzner console, not an unverified SSH session. Install both public keys,
the deployment principal, tailnet-only OpenSSH, and its constrained ownership:

```sh
sudo useradd --create-home --shell /bin/bash dev-server-deploy
sudo install -d -m 0700 -o dev-server-deploy -g dev-server-deploy \
  /home/dev-server-deploy/.ssh
printf '%s\n' 'DEPLOYMENT_PUBLIC_KEY' | sudo tee \
  /home/dev-server-deploy/.ssh/authorized_keys >/dev/null
sudo chown dev-server-deploy:dev-server-deploy \
  /home/dev-server-deploy/.ssh/authorized_keys
sudo chmod 0600 /home/dev-server-deploy/.ssh/authorized_keys
printf '%s\n' 'dev-server-deploy ALL=(ALL:ALL) NOPASSWD:ALL' | sudo tee \
  /etc/sudoers.d/90-dev-server-deploy >/dev/null
sudo chmod 0440 /etc/sudoers.d/90-dev-server-deploy
sudo visudo -cf /etc/sudoers.d/90-dev-server-deploy
sudo ufw allow in on tailscale0 to any port 22 proto tcp
sudo systemctl enable --now ssh
sudo tailscale set --ssh=false
```

Ensure `niels` still has the operator public key and no blanket passwordless
sudo. Record the server's Ed25519 host-key fingerprint from the console:

```sh
sudo ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub -E sha256
```

On the workstation, set the exact tailnet FQDN, scan only its Ed25519 key,
rewrite its host field to the stable alias, and compare the displayed SHA256
fingerprint byte-for-byte with the console value. Stop if they differ.

```sh
TAILNET_FQDN='dev-server.example-tailnet.ts.net'
scan_file="$(mktemp "$HOME/.ssh/dev-server.scan.XXXXXX")"
ssh-keyscan -T 10 -t ed25519 "$TAILNET_FQDN" 2>/dev/null |
  awk '{$1="dev-server"; print}' >"$scan_file"
chmod 0600 "$scan_file"
ssh-keygen -lf "$scan_file" -E sha256
```

After verification, replace only the exact `dev-server` entry atomically:

```sh
known_hosts="$HOME/.ssh/known_hosts"
known_candidate="$(mktemp "$HOME/.ssh/known_hosts.cutover.XXXXXX")"
touch "$known_hosts"
chmod 0600 "$known_hosts"
cat "$known_hosts" >"$known_candidate"
ssh-keygen -R dev-server -f "$known_candidate" >/dev/null
rm -f "$known_candidate.old"
cat "$scan_file" >>"$known_candidate"
chmod 0600 "$known_candidate"
mv "$known_candidate" "$known_hosts"
rm -f "$scan_file"
ssh -o BatchMode=yes -o IdentitiesOnly=yes \
  -o HostKeyAlias=dev-server -o StrictHostKeyChecking=yes \
  -i "$HOME/.ssh/id_ed25519" "niels@$TAILNET_FQDN" true
ssh -o BatchMode=yes -o IdentitiesOnly=yes \
  -o HostKeyAlias=dev-server -o StrictHostKeyChecking=yes \
  -i "$HOME/.ssh/dev-server-deploy" \
  "dev-server-deploy@$TAILNET_FQDN" sudo -n true
```

Trade-off: two SSH credentials and a manual, console-anchored host-key ceremony
add one-time work; remote agents no longer inherit deployment privilege.

### Every host: remove exact legacy installer state

Stop the Skíðblaðnir service using the native service manager. Preserve
`~/.config/skidbladnir/bearer`, `machine-handle`, AI credentials, Docker data,
SSH keys, Tailscale identity, and existing integration settings. Remove only:

```sh
rm -f "$HOME/.local/bin/skidbladnir"
rm -f "$HOME/.local/share/skidbladnir/characters.json"
rm -f "$HOME/.local/share/skidbladnir/release.json"
rm -f "$HOME/.local/share/skidbladnir/release-bundle.tar.gz"
rm -f "$HOME/.local/share/skidbladnir/.release-activation-required"
rm -f "$HOME/.local/share/skidbladnir/.converge.lock"
rm -f "$HOME/.config/skidbladnir/host-config.json"
rm -R "$HOME/.local/share/skidbladnir/.release-transaction"
```

On Arch, also disable and remove the exact retired user units and autostart:

```sh
systemctl --user disable --now xfce4-clipman.service
systemctl --user disable --now gammastep.service
systemctl --user disable --now app-com.mitchellh.ghostty.service
rm -f "$HOME/.config/systemd/user/xfce4-clipman.service"
rm -f "$HOME/.config/systemd/user/gammastep.service"
rm -f "$HOME/.config/systemd/user/app-com.mitchellh.ghostty.service"
rm -f "$HOME/.config/autostart/xfce4-clipman.desktop"
systemctl --user daemon-reload
```

Remove the former local cloud-state duplicate. On the devbox, also remove the
exact stale files from the user cache; do not use globs:

```sh
rm -f secrets/devbox-state.env
cache="$HOME/.local/share/dev-server"
rm -f "$cache/lib/doctor.sh"
rm -f "$cache/lib/packages-arch.sh"
rm -f "$cache/lib/packages-macos.sh"
rm -f "$cache/lib/remote-devbox.sh"
rm -f "$cache/lib/skidbladnir-invite.sh"
rm -f "$cache/lib/skidbladnir-operator.sh"
rm -f "$cache/skidbladnir"
rm -f "$cache/assets/routers/ai-router"
rm -f "$cache/assets/dotfiles/gammastep-autostart.desktop"
rm -f "$cache/assets/dotfiles/gammastep.config"
rm -f "$cache/assets/dotfiles/ghostty-autostart.desktop"
rm -f "$cache/assets/dotfiles/ghostty-xfce-helper.desktop"
rm -f "$cache/assets/dotfiles/ghostty.config"
rm -f "$cache/assets/dotfiles/xfce4-clipman-autostart.desktop"
rm -f "$cache/assets/dotfiles/xfce4-helpers.rc"
rm -f "$cache/assets/skidbladnir/agent-hooks-arch.json"
rm -f "$cache/assets/skidbladnir/agent-hooks-macbook.json"
rm -f "$cache/assets/skidbladnir/host-config-arch.json"
rm -f "$cache/assets/skidbladnir/host-config-macbook.json"
rm -f "$cache/assets/skidbladnir/dev.niels.skidbladnir.plist"
rm -f "$cache/assets/skidbladnir/skid-notify-macbook"
```

Finally retire only wrapper symlinks that still target the old router; preserve
plain upstream binaries and never remove `.codex*` or `.claude*` state:

```sh
router="$HOME/.local/libexec/ai-router"
for wrapper in \
  "$HOME/bin/codex" \
  "$HOME/bin/codex-personal" \
  "$HOME/bin/codex-work" \
  "$HOME/bin/codex-work2" \
  "$HOME/bin/claude" \
  "$HOME/bin/claude-personal" \
  "$HOME/bin/claude-work"
do
  if [ -L "$wrapper" ] && [ "$(readlink "$wrapper")" = "$router" ]; then
    rm -f "$wrapper"
  fi
done
rm -f "$router"
```

Ensure `~/.gitconfig.local` contains any machine-only identity/settings. Retire
the exact former GitHub SSH rewrite without hiding inspection errors:

```sh
if git config --global --get-all 'url.git@github.com:.insteadOf' >/dev/null; then
  git config --global --unset-all 'url.git@github.com:.insteadOf'
fi
```

The new pinned plugins are immutable generations behind managed links. They do
not adopt legacy in-place clones. Inspect each old clone with `git status`,
preserve any local work, then remove only these exact paths before apply:

```sh
rm -R "$HOME/.zsh/fzf-tab"
rm -R "$HOME/.zsh/powerlevel10k"
rm -R "$HOME/.tmux/plugins/tpm"
rm -R "$HOME/.tmux/plugins/tmux-resurrect"
rm -R "$HOME/.tmux/plugins/tmux-continuum"
```

Then run the appropriate apply command and verify the reported private
Skíðblaðnir health/Serve postconditions.

## Boundaries and trade-offs

- Native OS repositories are rolling rather than byte-replayable. Remote
  installers, AI CLIs, Git plugins, Cursor extensions, and Skíðblaðnir are exact
  reviewable pins and therefore can lag upstream until manually bumped.
- Native package and npm updates can partially complete; rerun their native
  reconcilers. Git plugin candidates are isolated until an atomic link switch.
  Only Skíðblaðnir has repository-owned service rollback.
- Skíðblaðnir no-op apply re-downloads its small archive to re-prove admission.
  A host-config-only change needs a new release pin because generation identity
  is release-keyed.
- Desktop login, reboot, busy Docker, and tmux-server activation are never
  forced. Public exposure, credentials, checksums, host-key continuity, and the
  last healthy Skíðblaðnir generation are never traded away for convenience.
- Existing-devbox safety repair may close or attach only the exact steady
  Hetzner firewall before tailnet reachability is available. An inactive UFW
  store is reset and rebuilt because its persisted rules cannot be observed
  safely while disabled.
- Immutable per-run input copies cost a small amount of local disk and I/O.
  Devbox Node.js is constrained to rolling major 24 rather than exact package
  bytes. Workstations accept their native candidate at version 24 or newer;
  those repositories remain the freshness authority and may advance majors.
- CI is hermetic and non-deploying. Final live applies, fleet/device acceptance,
  and release publication remain explicit operator actions.
- Arch fleet acceptance runs from an attached operator terminal and may prompt
  for sudo; the user/agent account never receives blanket passwordless
  elevation.
