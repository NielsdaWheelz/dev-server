# dev-server

one-user host configuration for `macbook`, `arch`, and the hetzner `devbox`.

```sh
./workstation apply
./devbox apply
```

`apply` installs declared configuration and missing requirements without seeking
newer installed packages or ai tools. use `upgrade` deliberately to update the
software and then apply the configuration:

```sh
./workstation upgrade
./devbox upgrade
```

an unchanged apply makes no managed-state change or service activation. exit
`0` means installed, with any deferred activation reported; `2` means an exact
manual action is required; `1` means failure; `64` means invalid invocation.
rerun after fixing the reported problem. `--help` lists the public commands.

[the specification](SPEC.md) defines ownership, activation, and failure behavior.
there are currently no automated tests, runner, or ci checks. direct verification
is required until [the test-system rebuild](docs/issues/test-system-rebuild.md).

## workstation

macos needs homebrew and the app store tailscale app, installed and signed in.
linux support is limited to the owned arch host, with pacman and yay. both need
git, curl, python 3, tmux, tailscale, and native service tools. existing github,
ai-tool, ssh, tailscale, and skid credentials are preserved.

arch operations run without a tty. supply `ARCH_PASS` through the environment
or the ignored repo `.env`, as `ARCH_PASS=your-password`, with file mode `0600`.
values are literal, with optional enclosing single or double quotes; the file
is never executed. the environment takes precedence. sudo uses the managed
askpass helper, and pacman/yay run noninteractively. missing or rejected
credentials fail before host changes. no passwordless sudo is granted.

`apply` checks that arch's declared packages are installed. missing packages
require `./workstation upgrade`, which performs a full system upgrade before
reconciling the aur manifest. this avoids unsupported partial upgrades.
macos apply uses homebrew's no-upgrade path; installing a missing formula can
still update dependencies needed by that formula. neither operation installs,
upgrades, replaces, or signs in to the app store tailscale app.

configuration is applied in order: native packages, dotfiles, exact-host personal
policy, ai tools/shared codex services, then skid. desktop login, reboot, busy
containers, and tmux binary activation are reported as `DEFERRED`. repo-owned
activation never forces them. native package installation/upgrade scripts can
still restart their services; schedule upgrades accordingly.

macos installs ghostty and its meslo font through homebrew. edit
[`assets/dotfiles/ghostty-macos.config`](assets/dotfiles/ghostty-macos.config);
apply installs it at
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`.
reload with `cmd+shift+,` or reopen ghostty. running terminals are left alone.

## ai accounts and services

`codex`, `codex-work`, and `codex-work2` select their existing account homes and
execute the single native binary at `~/.local/bin/codex`. `claude` and
`claude-work` use the single anthropic-native binary at `~/.local/bin/claude`.
wrappers preserve arguments, environment, cwd, and exit behavior.

`apply` retains valid installed versions and bootstraps a missing tool.
`upgrade` resolves codex's stable npm `latest` once and uses normal npm integrity
with scripts disabled; claude uses native `install latest`, independent of
account update-channel preferences. wrappers add no startup update lookup.
upstream tools retain their own behavior.

interactive zsh aliases add `--yolo` to the three codex commands and
`--dangerously-skip-permissions` to both claude commands. the defaults live in
[`assets/dotfiles/zsh_helpers`](assets/dotfiles/zsh_helpers). after applying,
start a shell or `source ~/.zsh_helpers`. `command codex`, `command claude`, and
the corresponding work names bypass the alias for one invocation.

```sh
codex-work login
codex-work2 resume
```

each host supervises three codex app servers, one per account. macbook uses
launchagents; arch uses user systemd services; devbox uses system services as
`niels`. workstation sockets are private at
`~/.local/run/codex-shared/<profile>/app-server.sock`. devbox grants only the
intended local client group access. account homes and credentials stay intact.

native discovery links each account's
`app-server-control/app-server-control.sock` to its supervised socket. a
conflicting path produces `ACTION`; apply never takes over another daemon.
compatible interactive launches can reuse the discovered server. native startup
overrides or an unavailable server can select an embedded backend. explicit
`--remote unix://…` requires attachment but has different command, cwd, config,
and resume semantics. the wrappers do not parse these choices.

shared tools execute in the server environment. calling-shell credentials are
not inherited, and long-lived-server config reload and full resume/config parity
are not promised. native daemon stop/restart cannot manage these supervised
services. after finishing active turns, explicitly restart them with:

```sh
./workstation apply --restart-codex
./devbox apply --restart-codex
```

`upgrade` accepts the same flag. without it, healthy running codex services keep
their current backend, even after a cli upgrade. changed operational inputs
produce `ACTION` before replacing the coupled files. the flag restarts all three
services even when their inputs are unchanged; tmux sessions survive.

[`assets/codex/profiles.json`](assets/codex/profiles.json) owns operational account
paths and principals. [`assets/agent-instructions.md`](assets/agent-instructions.md)
is installed into the five account homes as `AGENTS.md` or `CLAUDE.md`. edit the
repo source; apply replaces the installed copies. new sessions load changes.
[`assets/claude/statusline.sh`](assets/claude/statusline.sh) is installed as
`~/bin/claude-statusline` and set as the `statusLine` command in both claude
account `settings.json` files; running sessions pick it up on the next update.
project instructions, skills, other settings keys, history, and authentication
remain separately owned.

## agent fleet

run `skid`, `skid list`, `skid info reviewer`, or `skid enter reviewer`.
`skid --help` documents commands and automation; use `--json` and returned
`--ref` values for scripts. clients default to
`~/.config/skidbladnir/client.json`; `--machine arch` disambiguates a name.

new skid sessions use codex `--yolo` and claude
`--dangerously-skip-permissions`, with claude's identity plugin retained.
the three host configs own this policy. existing sessions keep their launch
arguments. `interrupt` retains a session; `stop` attempts provider halt and closes
it; `kill` closes only that terminal. linked work can survive another session.

release pins are authoritative. verified local artifacts are reused; unchanged
apply does not download the skid release again. configuration changes produce
an immutable runtime generation. failed activation restores the prior healthy
generation. `skid` and `skidbladnir` point to the same current binary.
local host-config admission remains until
[upstream provides a standalone validator](docs/issues/skid-config-validation.md).

provider control uses `~/.local/bin/provider-runtime-control`, installed from
[`assets/skidbladnir/native-control.json`](assets/skidbladnir/native-control.json).
the pinned source and frozen environment own provider dependencies. codex uses
terminal control/history; claude-work retains native state/history. provider
sockets stay local; peer control uses skid's authenticated private gateway.

fleet enrollment, bearer distribution, session operations, release acceptance,
and outage recovery belong to the
[skid repository](https://github.com/NielsdaWheelz/skidbladnir). its
`scripts/fleet provision-clients` provisions user clients and jarvis's client
configuration; rerun after an interrupted copy or bearer rotation.

## devbox

prerequisites:

- authenticated `hcloud` context `dev-infra`, local tailscale, `gh`, ssh,
  python 3, and `uvx`;
- operator key `~/.ssh/id_ed25519` and distinct deployment key
  `~/.ssh/dev-server-deploy`, regular private-key files with mode `0600`;
- `Include ~/.ssh/config.d/*` in the operator's ssh config;
- for a new server, a short-lived reusable tailscale auth key in
  `secrets/tailscale-auth-key`: one newline-terminated value, mode `0600`.

```sh
ssh-keygen -t ed25519 -f "$HOME/.ssh/dev-server-deploy" -C dev-server-deploy
chmod 0600 "$HOME/.ssh/dev-server-deploy"
install -d -m 0700 secrets
```

create the deployment key only if absent, place the bootstrap auth key in the
specified file, then run `./devbox apply`.

for a missing server, apply creates it, limits temporary public ssh to the
operator's exact ipv4 `/32`, establishes its openssh host key over the tailnet,
and removes bootstrap ingress on success or failure. an existing server uses
strict tailnet openssh as `dev-server-deploy`; it never opens public ssh or
resets host keys. `dev-server` remains the unprivileged `niels` operator alias.
missing github enrollment produces one exact manual action.

ansible owns ubuntu configuration. apply retains installed package versions;
upgrade selects current candidates. pgvector remains exactly pinned and held.
rootless docker setup is rebuilt only when its package, unit, or daemon config
changes and no container is running; otherwise activation is deferred.

this repository supplies jarvis's shared prerequisites: utc host time,
postgresql 16 and qualified pgvector, the `jarvis` account, and ownership of
`/opt/jarvis`, `/var/lib/jarvis`, and `/etc/jarvis`. the
[jarvis repository](https://github.com/NielsdaWheelz/jarvis) owns releases,
python environment, database/roles, migrations, service, credentials, and
backup/recovery. dev-server never deploys jarvis or touches nexus application
state. jarvis is independent of developer rootless docker.

jarvis cognition uses the existing shared codex services; worker tools use the
common skid cli and the target user's authority. the dedicated jarvis worker
launcher is retired.

## development

edit declarations, then apply on the intended host. use upgrade for rolling
software updates; review exact git, extension, native-control, and skid pin
changes in the repository. use subsystem-native status commands to investigate
a failure. there is no separate doctor or compatibility layer.

keep changes and verification proportional to this one-user system. record
unresolved work in [`docs/issues/`](docs/issues/), one file per issue; delete the
record when resolved. package-manager failures are repaired by rerunning their
native operation. only skid has repository-owned service rollback.
