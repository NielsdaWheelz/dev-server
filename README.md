# dev-server

one-user host configuration for `macbook`, `arch`, and the hetzner `devbox`.

```sh
./workstation apply
./devbox apply

# gateway maintenance is independent of shared host tools
./workstation gateway apply skidbladnir
./devbox gateway apply skidbladnir
```

gateway commands use skid's ordinary standalone installer. only devbox receives
the authoritative [personal yaml](assets/skidbladnir/config.yaml). the reviewed
standalone release pin is pending; apply reports action before any installation.

`gateway remove skidbladnir` delegates to `skid uninstall`; settings/private state,
tmux and shared packages are retained.
provider homes and signing files remain. herdr and herdr-mobile installation and
removal commands are retired. ordinary apply installs no herdr runtime, hook or gate and
never discards workers. [the maintenance runbook](docs/gateway-separation-runbook.md)
separates source changes from live acceptance.

`apply` updates rolling packages, maintains native codex, bootstraps missing
claude, reconciles exact repository pins, and installs shared host configuration. it replaces the former `upgrade`
command; there is no separate update mode. each run checks upstream releases,
so an unchanged checkout can still produce software updates. configuration-only
and offline applies are not supported.

already-converged configuration and pinned components are left alone.
native package managers and installers own update checks and bookkeeping. exit
`0` means installed, with any deferred activation reported; `2` means an exact
manual action is required; `1` means failure; `64` means invalid invocation.
rerun after fixing the reported problem. `--help` lists the public commands.

tmux follows the latest stable upstream release. homebrew and pacman install it
on the workstations; ubuntu builds the official release into `/usr/local` because
its distribution package lags upstream. every host verifies the installed version
against upstream. a lagging workstation repository fails apply rather than
silently accepting an older tmux. existing servers keep running until an explicit
maintenance restart; installing a new binary does not upgrade a running server.
after a version change, apply the skid gateway configuration before that restart
so its own detection agrees with the installation.
when starting an interactive tmux server from automation, clear inherited
`NO_COLOR` first (`env -u NO_COLOR tmux ...`); the server otherwise passes that
automation setting to new panes and their applications.

[the specification](SPEC.md) defines ownership, activation, and failure behavior.
there is no retained test suite or repository ci workflow. changes use temporary
integration tests and direct verification; evidence belongs in the pull request.

skid owns tmux workspace recovery. host apply removes the owned resurrect and
continuum entry points, preserving running sessions, saved layouts and inert
plugin generations; existing tpm retirement remains. run host apply before
activating a gateway with recovery. gateway-only apply does not perform this
host cutover. recovered panes start fresh shells; resume agent conversations
through their native commands.

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
personal policy, ai tools, supplied memory configuration. gateway
commands stage only their own inputs and reconcile only their own ingress. desktop login, reboot, busy containers, and tmux
binary activation are reported as `DEFERRED`. repo-owned activation never forces
them. native package installation/upgrade scripts can still restart their
services; schedule host applies accordingly. package changes have no automatic
rollback; native package managers own repair after a partial failure.

skid owns its service identity, xdg installation paths, dependencies and private
ingress. dev-server owns providers, account wrappers and personal desired yaml;
it installs no copied gateway, shell, ntfy or native-helper implementation.

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

the configured skid profile commands use these ordinary account wrappers.
explicit yaml retains codex `--yolo` and per-account `--remote` sockets, plus
claude's permission flag and personal identity plugin. the plugin is provisioned
under `~/.local/share/dev-server/claude-agent-identity`; skid injects no provider
flags or replacement shell functions. [the runbook](docs/gateway-separation-runbook.md#provider-and-jarvis-contract)
records the consumer and blocked jarvis deployment boundary.

normal `apply` on macbook, arch and devbox maintains codex through the checked
official installer even when its native command already works. this requires network
access, can advance the version on an unchanged checkout and can fail. upstream
defaults to latest unless its release selector, such as `CODEX_RELEASE`, says
otherwise. dev-server fixes the host-owner `HOME`, `CODEX_HOME=owner_home/.codex`
and `CODEX_INSTALL_DIR=owner_home/.local/bin`, independently of inherited
work-account selectors.
`UPDATED` means the before/after version differs; equal versions prove only no
observed version change. completed earlier operations remain after a failure;
there is no fallback or automatic rollback.

claude retains bootstrap/adoption only: missing commands use the official
installer; working native commands are not updated by apply. its
[activation-result defect](docs/issues/claude-native-update-activation.md) blocks
strict maintenance. invalid canonical commands are preserved and produce a
repair `ACTION`. apply does not restart provider sessions, update account
daemons, change account update settings or change npm's prefix.

future account and skid cli invocations follow the canonical selection without
a repository edit or gateway restart. direct `codex update` is not the checked
maintenance path: its [shell pipeline can hide download failure](docs/issues/codex-self-update-pipeline.md).
`codex-work update` also retains the separate
[upstream discovery limitation](docs/issues/codex-installation-discovery.md).
[the native maintenance runbook](docs/gateway-separation-runbook.md#native-ai-maintenance)
covers installation, manual context and repair. account daemons retain their
separate upstream-managed packages and updates.

account wrappers, native version inspection and the memory
configuration writer remove `CODEX_MANAGED_BY_NPM`, `CODEX_MANAGED_BY_BUN`,
`CODEX_MANAGED_BY_PNPM`, `CODEX_MANAGED_BY_VITE_PLUS` and
`CODEX_MANAGED_PACKAGE_ROOT` before invoking native codex. installer execution
clears the same keys and forces dedicated cli selection; the
[exact contract](SPEC.md#files-and-ai-tools) specifies preservation of upstream
release/transport selectors. selected accounts, memory credentials and existing
arguments remain intact. parent shells and running clients retain their
environments. profile-command changes use ordinary hub yaml application.

interactive zsh aliases add `--yolo` to codex commands and
`--dangerously-skip-permissions` to claude commands. the defaults live in
[`assets/dotfiles/zsh_helpers`](assets/dotfiles/zsh_helpers). after applying,
start a shell or `source ~/.zsh_helpers`. `command codex`, `command claude`, and
the corresponding work names bypass the alias for one invocation. skid's
personal yaml explicitly supplies permission arguments and its identity plugin.

```sh
codex-work login
codex-work2 resume
```

codex owns each account's native daemon and discovery socket. `codex` honors
a nonempty `CODEX_HOME`, otherwise selecting `.codex` under the host-user home
recorded when installed; `codex-work` and `codex-work2` always select their named
homes there, independently of runtime `HOME`. ordinary wrappers pass arguments
unchanged. ordinary account commands are stock launches; they do not acquire a native thread association. for sessions
created through skid, ordinary host AI apply prepares the account daemon and
the configured command explicitly launches `codex --remote unix://...`; codex creates its initial
thread. explicit native conversation references are separate from terminal
identity. native helper creation, inspection and canonical cli attachment use
that same selected daemon. the socket comes from the selected `CODEX_HOME` at
`app-server-control/app-server-control.sock`. the installer owns no daemon
bootstrap, service or package policy.

host-owned codex daemon starts pass through each ordinary account wrapper,
loading only its memory credential before native exec. skid does not manage
daemon startup, upgrade or shutdown.

the former shared codex services and exact discovery links are retired;
cleanup-only deployment code is gone. account homes, credentials and native
daemon sockets remain upstream-owned. jarvis cognition recovery and activation
are separate owner tasks.

ordinary devbox apply installs ubuntu's bubblewrap apparmor profile and
configures earlyoom to prefer preserving codex and claude. development user
services get the same zero oom adjustment as login-shell workloads; apply
repairs the former inherited +200 without restarting those workloads. under
severe memory pressure, builds and editors can still be killed; the preference
does not make agents immune.

[`assets/agent-instructions.md`](assets/agent-instructions.md)
is installed into the five account homes as `AGENTS.md` or `CLAUDE.md`. edit the
repo source; apply replaces the installed copies. new sessions load changes.
[`assets/claude/statusline.sh`](assets/claude/statusline.sh) is installed as
`~/bin/claude-statusline` and set as the `statusLine` command in both claude
account `settings.json` files; running sessions pick it up on the next update.
every host installs the same display-only command. it renders context usage and
optional 5-hour/weekly used quota from claude's structured statusline input.
skid observes these displayed figures in tmux; absent or unrecognized usage stays
unknown. the formatter stores no quota report.
account update settings, project instructions, skills, other settings keys,
history and authentication remain separately owned. both claude homes set
`cleanupPeriodDays` to 36,500; this retains other application data as well as
conversation history and increases disk use. claude documents no supported
disable sentinel. [claude directory reference](https://code.claude.com/docs/en/claude-directory).

## universal memory

jarvis owns the shared corpus, private server, admission and stopped cutover.
this repository owns host collectors and native client configuration. the
[default declaration](assets/memory/declaration.example.json) lists all sixteen
lanes with admission and connection disabled. record actual controllers,
sharing authorization, recipients and processors before enabling a lane.
native developer profiles do not grant nexus application chats access.

render the private bundle with the qualified central jarvis release's python:

```sh
"$JARVIS_RELEASE/.venv/bin/python" scripts/memory-config.py \
  --declaration secrets/memory/declaration.json \
  --credentials secrets/memory/credentials.json \
  --output secrets/memory/bundle \
  --url "$MEMORY_URL" \
  --home "macbook=$MACBOOK_HOME" \
  --home "arch=$ARCH_HOME" \
  --home "devbox=$DEVBOX_HOME"
```

declare the same origin in the input; devbox requires its private tailscale
HTTPS origin. rendering creates missing scoped bearers once and preserves
existing credentials. `--rotate capture:macbook` or
`--rotate client:macbook:codex-personal` rotates only the named current identity.
the entire generated bundle is private; only `server.json` contains hashes.
jarvis's installer consumes that file separately. distribute only each host's
own directory under ignored `secrets/memory/bundle/<host>`.

the optional `nexus_client` declaration names one configured viewer and the
complete selected model processor labels. its separately scoped backend bearer
is rendered only in `bundle/nexus/client.json`, consumed through Nexus's
`MEMORY_CLIENT_CONFIG_PATH`. undeclared/disconnected clients receive the explicit
`Absent` shape. `--rotate client:nexus-owner` rotates that credential only.
owner send/rerun/regenerate may read shared memory and append admitted notes;
other viewers, automated helpers and Nexus conversations gain no capture.

ordinary `apply` installs a collector from
[`release-pin.json`](assets/memory/release-pin.json) and reconciles connected
profiles. it neither changes sharing authority nor rotates credentials. the
collector is a launchd owner job on macbook or a systemd user unit on linux.
before preparing a new release, supply ordinary authenticated git read access to
the private universal-memory dependency under that owner account. this build
authorization stays outside the bundle and collector/native runtime environment.
an absent bundle or pending source pin reports an action. verification failure
reports deferred activation without advancing the active digest.

connected native profiles load a private bearer environment for future launches
and the native `jarvis-memory` entry at `/v1/mcp`. they receive the exact product
memory instruction; existing native agents and daemons remain running. the
native configuration contracts are
[codex MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli) and
[claude MCP](https://code.claude.com/docs/en/mcp). actual loaded connections need
their own acceptance. devbox owns only private HTTPS 443 `/v1`, preserving skid's
8443 endpoint and unrelated handlers; funnel and foreign owned handlers refuse
activation. [remaining host qualification](docs/issues/universal-memory-activation.md).

## agent fleet

[personal yaml](assets/skidbladnir/config.yaml) retains profile keys, labels,
order, accounts and effective provider options. devbox is the desired hub;
macbook keeps ghostty notifications, and each host retains its login shell and
self-selection default. explicit root-owned enrollment/conversion preserves
machine handles/order and notification memory. dev-server writes no roster or
generated runtime config.

on devbox, `~/.config/dev-server/skidbladnir.yaml` (or the matching xdg config
path) may supply the complete personal yaml instead of the committed file.
keep it mode `0600`. this host-owned file is authoritative when present; apply
copies it whole, without merging. optional firebase public options belong here;
the service-account private key remains in its separately configured private file.

`lib/skidbladnir.sh` delegates installation and removal to the standalone skid
installer. the release pin names a version, source commit and bootstrap sha256;
the ordinary bootstrap verifies signed archives. the current pending pin refuses
installation until the reviewed matching release is published. normal skid
updates own services/shell integration and preserve settings, tmux and providers.
old ntfy, copied gateway/native helper assets and deployment rollback code are
removed; there is no old-wire fallback. see [the maintenance runbook](docs/gateway-separation-runbook.md).

ordinary host AI apply starts/reuses each declared codex daemon through upstream
commands; it never restarts/upgrades that daemon. skid does no daemon lifecycle
work. a later upstream cli change still needs compatibility qualification.

jarvis's source adapter uses the matching cli and live installed computer state,
with no launch model/effort overrides. its service uid cannot read the enrolled
host user's private state under existing containment. installed worker cutover
is BLOCKED pending separate jarvis service-state integration. source checks are
neither that qualification nor fleet/phone deployment. preserve unrelated
settings, provider history and all existing workers throughout cutover.

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
| memory bundle, collectors and native client configuration | `scripts/memory-config.py`, `lib/memory.sh`, `assets/memory/`, `ansible/roles/memory/` |
| devbox github identity and ssh client policy | `ansible/roles/github/`; `devbox` owns account enrollment checks |
| standalone skid consumer and personal yaml | `lib/skidbladnir.sh`, `assets/skidbladnir/` |
| personal identity plugin | `lib/ai-tools.sh`, `assets/claude/agent-identity/` |
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
