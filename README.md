# dev-server

one-user host configuration for `macbook`, `arch`, and the hetzner `devbox`.

```sh
./workstation apply
./devbox apply

# gateway maintenance is independent of shared host tools
./workstation gateway apply skidbladnir
./devbox gateway apply skidbladnir
```

`gateway remove skidbladnir` removes skid's gateway and owned serve handler;
provider homes and signing files remain. herdr and herdr-mobile installation and
removal commands are retired. ordinary apply installs no herdr runtime, hook or gate and
never discards workers. [the maintenance runbook](docs/gateway-separation-runbook.md)
separates source changes from live acceptance.

`apply` updates rolling packages and ai tools, reconciles exact repository pins,
and installs shared host configuration. it replaces the former `upgrade`
command; there is no separate update mode. each run checks upstream releases,
so an unchanged checkout can still produce software updates. configuration-only
and offline applies are not supported.

already-converged configuration and pinned components are left alone.
native package managers and installers own update checks and bookkeeping. exit
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

arch `apply` performs a full `pacman -Syu` with the declared packages before
reconciling the aur manifest. this avoids unsupported partial upgrades.
macos `apply` refreshes homebrew metadata and upgrades declared formulae and
casks. the app store tailscale app remains separately owned: apply verifies
and optionally starts it, but never installs, updates, replaces, or signs in to it.

host configuration is applied in order: native packages, dotfiles, exact-host
personal policy, ai tools. gateway
commands stage only their own inputs and reconcile only their own ingress. desktop login, reboot, busy containers, and tmux
binary activation are reported as `DEFERRED`. repo-owned activation never forces
them. native package installation/upgrade scripts can still restart their
services; schedule host applies accordingly. package changes have no automatic
rollback; native package managers own repair after a partial failure.

deployment identity uses `dev_server_home_dir` (`$HOME`),
`dev_server_fleet_label_prefix` (`dev.niels`) and `dev_server_gateway_port`
(`7341`). skid's mac plist is rendered in its private stage. linux identity is
the user account and skid's systemd unit. [the specification](SPEC.md#deployment-identity)
defines disposable qualification and isolation requirements.

arch touchpad policy lives in
[`assets/xorg/90-dev-server-huawei-touchpad.conf`](assets/xorg/90-dev-server-huawei-touchpad.conf).
xorg loads it when the display server starts. apply reports `DEFERRED` on every
run while an existing xorg process predates the installed policy; restart the
display server or reboot when convenient. this timestamp check tracks pending
activation, not device behavior. `xorg-xinput` is no longer required; apply
does not remove an already installed package.

macos installs ghostty and its meslo font through homebrew. edit
[`assets/dotfiles/ghostty-macos.config`](assets/dotfiles/ghostty-macos.config);
apply installs it at
`~/Library/Application Support/com.mitchellh.ghostty/config.ghostty`.
reload with `cmd+shift+,` or reopen ghostty. running terminals are left alone.

## ai accounts and services

ordinary shells keep the established provider binaries and account
commands: `.codex`, `.codex-work`, `.codex-work2`, `.claude`, `.claude-work`.
their authentication, configuration, history, memories, plugins and trust stay
in place. existing environment-override semantics remain intact.

original skid's forge and marked bash/zsh terminals use those same accounts
through scoped commands. skid invokes codex's upstream npm native executable and
the shared native claude command directly. personal claude leaves
`CLAUDE_CONFIG_DIR` unset. skid loads its claude identity plugin explicitly; it
installs no codex hooks and never provisions or rewrites account state.
[the runbook](docs/gateway-separation-runbook.md#provider-and-jarvis-contract)
gives the exact worker map and app environment contract.

`apply` resolves codex's stable npm `latest` once per run on every host
and installs it when needed under `~/.local`. npm owns package integrity;
installation disables scripts and verifies the package and executable versions.
claude reconciles the exact qualified native version declared in
`assets/skid-provider/native-control.json`. account update settings remain
user-owned; apply repairs version drift without restarting provider sessions.

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

codex owns each account's native daemon and discovery socket. `codex` honors
an existing `CODEX_HOME`, otherwise selecting `.codex`; `codex-work` and
`codex-work2` always select their named homes. the wrappers pass arguments
unchanged to the installed cli. manual marked-shell commands are ordinary
stock launches; they do not acquire a native thread association. for sessions
created through skid, the host starts or reuses the selected account's upstream
daemon, creates a native thread, then launches `codex --remote unix://... resume`
with that thread id. the socket comes from the selected `CODEX_HOME` at
`app-server-control/app-server-control.sock`. the installer owns no daemon
bootstrap, service or package policy.

on the devbox, apply retires the former shared services and their exact
discovery links before reconciling ai tools. when those services are present,
it first stops and disables jarvis, whose deployed cognition depends on them.
jarvis cognition recovery through the shared app-server belongs to its owner;
worker deployment can proceed while jarvis remains stopped.
subsequent applies leave a separately repaired jarvis service alone. account
homes, credentials and native daemon sockets are preserved.

ordinary devbox apply installs ubuntu's bubblewrap apparmor profile and
configures earlyoom to prefer preserving codex and claude. under severe memory
pressure, builds and editors can still be killed; the preference does not make
agents immune.

[`assets/agent-instructions.md`](assets/agent-instructions.md)
is installed into the five account homes as `AGENTS.md` or `CLAUDE.md`. edit the
repo source; apply replaces the installed copies. new sessions load changes.
[`assets/claude/statusline.sh`](assets/claude/statusline.sh) is installed as
`~/bin/claude-statusline` and set as the `statusLine` command in both claude
account `settings.json` files; running sessions pick it up on the next update.
account update settings, project instructions, skills, other settings keys,
history and authentication remain separately owned.

## agent fleet

skid owns the tmux gateway and native provider helper on each host: loopback
`7341`, private tailscale `8443 /v1`, existing account homes and pairings.
its unit, launcher, config, bearer, machine handle and rollback generations are
independent of provider history. gateway maintenance never kills tmux workers.

jarvis uses `/usr/local/libexec/skidbladnir`, a regular root:root `0755` copy of
the same admitted devbox gateway artifact. gateway apply compares both installed
cli and running gateway bytes before activation. a changed executable requires
jarvis paused and cleanly stopped; identical apply is inert. jarvis deploy owns
the explicitly supplied private `/etc/jarvis/agent-client.json`, its settings and
service containment. bearer rotation requires private-client redistribution.

[`assets/skidbladnir`](assets/skidbladnir) owns the release pin and host template;
[`assets/skid-provider`](assets/skid-provider) owns scoped provider commands and
the separately pinned stock native helper. the admitted binary validates config.
failed activation restores only skid's verified prior generation. provider
binaries remain shared host tools, and signing material stays outside installer
validation. phone enrollment and device acceptance belong to the app owner.

the root operator completed herdr and herdr-mobile retirement on all three hosts:
owned runtimes, integrations, ssh gates, credentials and `8444 /v1` are removed.
cleanup-only code is deleted. preserve unrelated settings and serve handlers,
provider history, skid workers and permanent signing backups. normal host apply,
gateway apply and installed native lifecycle passed on all three hosts with
skid `v0.10.6` and stock codex `0.159.2`. fleet tls, the production client under
the actual jarvis uid, and owner phone attachment also passed on all three.
jarvis remains disabled, inactive and paused; activation and cognition are
separate. [qualification](docs/gateway-separation-validation.md#2026-09-29-installed-fleet)
records the evidence and deferred reboots.

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
does apply save that key. public ssh is never opened.

an existing server uses strict tailnet openssh as `dev-server-deploy` and never
resets host keys. if creation stops before key enrollment, inspect cloud-init,
tailscale, and `/etc/ssh/ssh_host_ed25519_key.pub` through the hetzner console.
verify and enroll that key locally under `dev-server` before rerunning apply;
there is no automatic trust reset. `dev-server` remains the unprivileged `niels`
operator alias. missing github enrollment produces one exact manual action.

ansible owns ubuntu configuration. apply refreshes package metadata and selects
current candidates for declared packages. pgvector remains exactly pinned and
held. a reviewed change to the qualified pgvector pin authorizes its upgrade or
rollback on apply; application and database compatibility qualification belongs
to jarvis.
rootless docker setup is rebuilt only when its package, unit, or daemon config
changes and no container is running; otherwise activation is deferred.

this repository supplies jarvis's shared prerequisites: utc host time,
postgresql 16 and qualified pgvector, the `jarvis` account, and ownership of
`/opt/jarvis`, `/var/lib/jarvis`, and `/etc/jarvis`. the
[jarvis repository](https://github.com/NielsdaWheelz/jarvis) owns releases,
python environment, database/roles, migrations, service, credentials, and
backup/recovery. dev-server never deploys jarvis or touches nexus application
state. jarvis is independent of developer rootless docker.

the former codex service installation is retired during host apply. cognition
recovery using the shared app-server remains separately owned; worker deployment
can proceed with jarvis stopped. its worker tools
reach each host through the fixed skid cli (see [agent fleet](#agent-fleet)).

## development

| slice | owner |
|---|---|
| command orchestration | `workstation`, `devbox` |
| file installation and result reporting | `lib/common.sh` |
| workstation packages, personal policy, dotfiles, tmux activation | `lib/packages-*.sh`, `lib/personal-*.sh`, `lib/dotfiles.sh`, `lib/tmux.sh` |
| ai binaries and account commands | `lib/ai-tools.sh`, `assets/routers/ai-profile` |
| devbox github identity and ssh client policy | `ansible/roles/github/`; `devbox` owns account enrollment checks |
| gateway ownership and shared activation | `lib/skidbladnir.sh`, `lib/gateway-runtime.sh`, `assets/skidbladnir/` |
| scoped skid commands and helper | `lib/skid-provider.sh`, `assets/skid-provider/` |
| devbox host configuration | `ansible/roles/`, `cloud-init-devbox.template.yaml` |

work one bounded slice per pr, following the
[verification workflow](SPEC.md#verification-and-development). keep validation
and activation with the subsystem that owns the state.

edit declarations, then apply on the intended host. apply includes rolling
software updates; review exact git, extension and skid pin
changes in the repository. use subsystem-native status commands to investigate
a failure. there is no separate doctor or compatibility layer.

keep changes and verification proportional to this one-user system. record
unresolved work in [`docs/issues/`](docs/issues/), one file per issue; delete the
record when resolved. package-manager failures are repaired by rerunning their
native operation. only skid has repository-owned service rollback.
