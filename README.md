# dev-server

one-user host configuration for `macbook`, `arch`, and the hetzner `devbox`.

```sh
./workstation apply
./devbox apply

# gateway maintenance is independent of shared host tools
./workstation gateway apply herdr-mobile
./workstation gateway apply skidbladnir
./devbox gateway apply herdr-mobile
./devbox gateway apply skidbladnir
```

`gateway remove <product>` removes only the selected gateway and its owned
serve handler; provider homes and signing files remain. herdr-mobile `v0.9.0`
is pinned; original skid's first separated release remains pending. follow
[the cutover runbook](docs/gateway-separation-runbook.md) before any live
namespace change.

ordinary `apply` installs shared host configuration and missing requirements without seeking
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
there is no retained test suite or repository ci workflow. changes use temporary
integration tests and direct verification; evidence belongs in the pull request.

tmux loads the pinned resurrect and continuum plugins directly. this repo owns
their installation and updates; tpm is retired. apply removes its managed
checkout and bindings while preserving running sessions and saved layouts.

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

host configuration is applied in order: native packages, dotfiles, exact-host
personal policy, ai tools/shared codex services, then upstream herdr. gateway
commands stage only their own inputs and reconcile only their own ingress. desktop login, reboot, busy containers, and tmux
binary activation are reported as `DEFERRED`. repo-owned activation never forces
them. native package installation/upgrade scripts can still restart their
services; schedule upgrades accordingly.

deployment identity uses `dev_server_home_dir` (`$HOME`),
`dev_server_fleet_label_prefix` (`dev.niels`), `dev_server_gateway_port` (`7341`
for original skid) and `dev_server_mobile_gateway_port` (`7342`). mac plists
are rendered only for the selected owner. linux identity is the user account
and product's distinct systemd unit. [the specification](SPEC.md#deployment-identity)
defines disposable qualification and isolation requirements.

arch touchpad policy lives in
[`assets/xorg/90-dev-server-huawei-touchpad.conf`](assets/xorg/90-dev-server-huawei-touchpad.conf).
xorg loads it when the display server starts. apply reports `DEFERRED` on every
run while an existing xorg process predates the installed policy; restart the
display server or reboot when convenient. this timestamp check tracks pending
activation, not device behavior. `xorg-xinput` is no longer required; apply and
upgrade do not remove an already installed package.

macos installs ghostty and its meslo font through homebrew. edit
[`assets/dotfiles/ghostty-macos.config`](assets/dotfiles/ghostty-macos.config);
apply installs it at
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`.
reload with `cmd+shift+,` or reopen ghostty. running terminals are left alone.

## ai accounts and services

ordinary and herdr shells keep the established provider binaries and account
commands: `.codex`, `.codex-work`, `.codex-work2`, `.claude`, `.claude-work`.
their authentication, configuration, history, memories, plugins and trust stay
in place. existing environment-override semantics and native herdr integrations
remain intact; jarvis keeps its existing worker map and cognition services.

only original skid's forge and marked bash/zsh terminals use its scoped
launcher and fresh homes under `~/.local/share/skidbladnir/providers/`.
authenticate normally and inspect/trust skid's hooks there; do not copy account
trees or discovery sockets. skid invokes codex's packaged native executable
and the shared native claude command directly.
[the runbook](docs/gateway-separation-runbook.md#provider-and-jarvis-contract)
gives the exact worker map and app environment contract.

`apply` retains valid installed versions and bootstraps a missing tool, except
that devbox codex always reconciles its declared pin.
`upgrade` keeps that devbox pin; elsewhere it resolves codex's stable npm
`latest` once. npm installation uses normal integrity checks with scripts
disabled; claude uses native `install latest`. both claude
accounts follow `latest`: apply enforces that shared policy and removes
account version floors. claude's native auto-updater handles background updates
and old-version cleanup. wrappers add no startup update lookup.

interactive zsh aliases add `--yolo` to codex commands and
`--dangerously-skip-permissions` to claude commands. the defaults live in
[`assets/dotfiles/zsh_helpers`](assets/dotfiles/zsh_helpers). after applying,
start a shell or `source ~/.zsh_helpers`. `command codex`, `command claude`, and
the corresponding work names bypass the alias for one invocation. skid's
own launcher supplies these permission arguments and its identity plugin.

```sh
codex-work login
codex-work2 resume
```

the devbox supervises three codex app servers, one per account, as system
services running as `niels`, for jarvis's cognition; it grants only the intended
local client group access and pins codex 0.155.1 (see
[issue](docs/issues/codex-daemon-socket.md)). macbook and arch run no shared
server; interactive codex there runs embedded. account homes and credentials
stay intact.

native discovery links each account's
`app-server-control/app-server-control.sock` to its supervised socket. a
conflicting path produces `ACTION`; apply never takes over another daemon.
normal account clients retain this native discovery behavior. original skid's
private homes have no copied discovery links; their sessions run embedded. explicit
`--remote unix://…` requires attachment but has different command, cwd, config,
and resume semantics. the wrappers do not parse these choices.

shared tools execute in the server environment. calling-shell credentials are
not inherited, and long-lived-server config reload and full resume/config parity
are not promised. native daemon stop/restart cannot manage these supervised
services. after finishing active turns, explicitly restart them with:

```sh
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
the repo also owns `autoUpdatesChannel` and removes `minimumVersion` in both
accounts. project instructions, skills, other settings keys, history, and
authentication remain separately owned.

## agent fleet

herdr-mobile is the phone gateway to upstream herdr. original skidbladnir is
an independent tmux product. each has its own unit, launcher, config, bearer,
machine handle, operator client and rollback chain. herdr-mobile listens on
loopback `7342` behind private tailscale `8444/v1`; skid uses `7341` and
`8443/v1`. removing either gateway preserves the other and both worker runtimes.

upstream herdr remains one pinned server per host from
[`assets/herdr/release-pin.json`](assets/herdr/release-pin.json), supervised
independently. changing its runtime while it runs requires an explicit stop
because stopping ends its terminals and agents. herdr integrations remain in
the existing normal account homes. original skid has its own private homes,
hooks and separately pinned native helper. provider binaries and tailscale
remain shared host tools with separate upgrade operations.

host templates live under [`assets/herdr-mobile`](assets/herdr-mobile) and
[`assets/skidbladnir`](assets/skidbladnir). each admitted binary validates its
own config. verified artifacts are reused and failed activation restores only
that product's verified prior release. the old herdr-backed v0.8 gateway is
never an original skid rollback target. no gateway installer reads android
signing material.

to reach another host's herdr, attach with `herdr --remote niels@dev-server`
(or `nnandal@arch`, `nnandal@niels-eriks-macbook-pro`) or run one command with
`ssh dev-server herdr agent list`. `--remote` starts a server on the target if
none is listening, so do not use it while that host's herdr is stopped for a
pin change. dev-server saves no herdr machines
([issue](docs/issues/herdr-saved-machines.md)); these ssh keys and known hosts
are yours to set up.

jarvis reaches every host through `~/.local/libexec/herdr-gate`, bound to its
key in each owner account's `authorized_keys`; the gate runs only an allowlist
of agent and pane commands. it is policy hygiene, not containment: pane ids are
not scoped to jarvis's panes. the key is generated on devbox and its public
half is committed as the trust root. the gate's allowed home values must match
jarvis's existing worker map. provider homes, cognition services and discovery
remain unchanged during the gateway cutover.

rebuilding devbox changes its host key and its jarvis key: update the `devbox`
line in [`assets/herdr/jarvis-known_hosts`](assets/herdr/jarvis-known_hosts)
and the workstations' `known_hosts`, recommit `jarvis-gate.pub` from the
reported line, and apply every host. apply removes the old key's gate line.

phone enrollment, release acceptance and device recovery belong to each app
owner. the cutover operator verifies repository ids before using the final
`herdr-mobile` and `skidbladnir` names; github redirects do not establish identity.

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

for a missing server, apply creates it with the steady private firewall, waits
for tailscale enrollment, and establishes its openssh host key over the tailnet.
initial trust relies on the unique named peer authenticated by tailscale; the
peer name is not a cryptographic binding to the hetzner server id. only after
cloud-init succeeds, native openssh is confirmed, and both principals authenticate
does apply save that key. public ssh is never opened. a new server also has a
new jarvis gate key and host key; recommit both as described under
[agent fleet](#agent-fleet).

an existing server uses strict tailnet openssh as `dev-server-deploy` and never
resets host keys. if creation stops before key enrollment, inspect cloud-init,
tailscale, and `/etc/ssh/ssh_host_ed25519_key.pub` through the hetzner console.
verify and enroll that key locally under `dev-server` before rerunning apply;
there is no automatic trust reset. `dev-server` remains the unprivileged `niels`
operator alias. missing github enrollment produces one exact manual action.

ansible owns ubuntu configuration. apply retains installed package versions;
upgrade selects current candidates. pgvector remains exactly pinned and held.
a reviewed change to the qualified pgvector pin authorizes its upgrade or rollback
on either command. package metadata refreshes when the installed version differs;
application and database compatibility qualification belongs to jarvis.
rootless docker setup is rebuilt only when its package, unit, or daemon config
changes and no container is running; otherwise activation is deferred.

this repository supplies jarvis's shared prerequisites: utc host time,
postgresql 16 and qualified pgvector, the `jarvis` account, and ownership of
`/opt/jarvis`, `/var/lib/jarvis`, and `/etc/jarvis`. the
[jarvis repository](https://github.com/NielsdaWheelz/jarvis) owns releases,
python environment, database/roles, migrations, service, credentials, and
backup/recovery. dev-server never deploys jarvis or touches nexus application
state. jarvis is independent of developer rootless docker.

jarvis cognition uses the existing shared codex services; its worker tools
reach each host's herdr through the gate (see [agent fleet](#agent-fleet)).

## development

| slice | owner |
|---|---|
| command orchestration | `workstation`, `devbox` |
| file installation and result reporting | `lib/common.sh` |
| workstation packages, personal policy, dotfiles, tmux activation | `lib/packages-*.sh`, `lib/personal-*.sh`, `lib/dotfiles.sh`, `lib/tmux.sh` |
| ai binaries, accounts, shared services | `lib/ai-tools.sh`, `assets/codex/`, `assets/routers/ai-profile` |
| devbox github identity and ssh client policy | `ansible/roles/github/`; `devbox` owns account enrollment checks |
| herdr runtime and integrations, jarvis's gate | `lib/herdr.sh`, `assets/herdr/`, `ansible/roles/jarvis_herdr/` |
| gateway ownership and shared activation | `lib/herdr-mobile.sh`, `lib/skidbladnir.sh`, `lib/gateway-runtime.sh`, `assets/{herdr-mobile,skidbladnir}/` |
| private provider homes and skid helper | `lib/provider-homes.sh`, `lib/skid-provider.sh`, `assets/skid-provider/` |
| devbox host configuration | `ansible/roles/`, `cloud-init-devbox.template.yaml` |

work one bounded slice per pr, following the
[verification workflow](SPEC.md#verification-and-development). keep validation
and activation with the subsystem that owns the state.

edit declarations, then apply on the intended host. use upgrade for rolling
software updates; review exact git, extension, herdr, and skid pin
changes in the repository. use subsystem-native status commands to investigate
a failure. there is no separate doctor or compatibility layer.

keep changes and verification proportional to this one-user system. record
unresolved work in [`docs/issues/`](docs/issues/), one file per issue; delete the
record when resolved. package-manager failures are repaired by rerunning their
native operation. only skid has repository-owned service rollback.
