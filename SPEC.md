# host configuration contract

`dev-server` manages the three owned hosts: `macbook`, `arch`, and `devbox`.
its job is to install declared state, activate affected consumers, verify the
critical result, and report mutations, deferrals, or required actions.

## commands and update policy

```text
./workstation {apply|upgrade}
./devbox {apply|upgrade} [--restart-codex]
./workstation gateway {apply|remove} {herdr-mobile|skidbladnir}
./devbox gateway {apply|remove} {herdr-mobile|skidbladnir}
./workstation {help|--help|-h}
./devbox {help|--help|-h}
```

`apply` reconciles configuration and missing requirements. it does not seek
newer installed os packages or ai tools. repository pins remain desired state:
a changed pin is applied deliberately, including on ordinary apply.
`upgrade` updates rolling software and then applies the same configuration.
`--restart-codex` separately authorizes interruption of the devbox's three codex servers.

gateway operations select one product and leave shared host tools and upstream
herdr alone. ordinary host apply/upgrade does not install either gateway.
published release pins are prerequisites for gateway apply; neither the old
herdr-backed v0.8 pin nor original skid's stale v0.6 pin is admissible as a
separated release. source preparation and live namespace handback are distinct
operations; see [the cutover runbook](docs/gateway-separation-runbook.md).

| owner | apply | upgrade |
|---|---|---|
| homebrew | install missing declarations without auto-update or bundle upgrades | update metadata and upgrade declared packages |
| pacman/yay | require declared packages; missing ones produce an action | full `pacman -Syu`, then declared aur packages |
| ubuntu apt | installed packages remain; missing requirements may refresh metadata | reconcile declared packages to repository candidates |
| codex/claude | reconcile the devbox codex pin; otherwise verify and retain installed versions; bootstrap missing tools | reconcile the devbox codex pin; elsewhere install stable codex npm `latest`; install native claude `latest` |
| repo pins | install declared exact versions | same |

homebrew can upgrade dependencies required by a missing formula. arch partial
upgrades are forbidden. ubuntu unattended security updates remain independently
owned by their native service. pgvector stays exactly pinned and held. neither
command removes packages, upgrades the distribution, recreates a vps, reboots,
logs out, or kills tmux. repo-owned docker activation defers while containers
run; native package installation/upgrade scripts can still restart their
services. an upgrade is not a zero-interruption guarantee.

an unchanged apply must make no managed-state mutation or activation and open
no ingress. package-manager metadata is not managed state. exit `0` means
installed with explicit deferrals; `2` means manual action; `1` means failure;
`64` means invalid invocation. no operation is implied when omitted.

result vocabulary is `INSTALLED`, `UPDATED`, `CHANGED`, `STARTED`, `RELOADED`,
`RESTARTED`, `DEFERRED`, `ACTION`, `UP TO DATE`, and `ERROR`. emit changes/actions
and one summary; native diagnostics may pass through. report `UP TO DATE` only
when no deferral remains.

## ownership and execution

orchestrators select the exact host, check controller prerequisites, stage a
coherent copy of declared input bytes and modes, and verify that copy before
consumption. source edits during a run cannot mix configuration revisions.
do not repeatedly hash the same staged closure after each subsystem.

subsystems own validation of their input declarations and installed state at
the mutation boundary. orchestration must not duplicate their schemas or
reimplement their state checks in a global remote preflight. ordinary managed
configuration drift is repaired through the owning installer. credentials,
foreign sockets, and privileged ownership conflicts require explicit action.
a later subsystem failure can leave earlier changes applied; rerun after repair.
there is no whole-host transaction or duplicated all-host admission gate.

workstation host apply orders native packages, dotfiles, exact-host personal
policy, ai tools/shared codex, herdr, then remaining postconditions. a gateway
operation stages only its own declaration closure, checks its owned ingress,
and applies/removes that gateway and handler. neither gateway operation runs
upstream herdr preflight or host-tool provisioning. linux is supported
only on the exact owned arch host. arch elevation uses `ARCH_PASS` through
askpass, including yay; values come from the environment or literal ignored
repo `.env`, never evaluation. validate credentials before host changes.

ansible owns ubuntu packages, privileged configuration, and native handlers.
it consumes the staged controller closure and reports real changes. native
package managers own resolution and partial-install repair; there is no package
rollback layer.

`lib/common.sh` owns atomic file installation, hashes, and result rendering.
subsystems own their activation state and pending deferrals.
the shared library does not own package policy, service names, product schemas, or a
workflow engine. product configuration semantics belong to the product;
deployment declarations own host paths, pins, identities, and launch arguments.

## durable writes and activation

managed files use compare-before-write and same-filesystem atomic promotion.
verify bytes and mode before rename; preserve credentials and account state.
a managed file is entirely repo-owned except explicitly named parser-backed
keys, currently cursor's `remote.SSH.remotePlatform`, claude's `statusLine`,
`autoUpdatesChannel`, and `minimumVersion`, and jarvis's gate lines in the
owner's `~/.ssh/authorized_keys`.
intentional symlinks have explicit owners and targets; do not overwrite
conflicting foreign paths.

critical activation compares desired identity with observed/recorded active
identity, not just this run's file changes. record active identity only after
successful activation and functional verification. a config file on disk is
not proof that a running service loaded it.

active digests live at `~/.local/state/dev-server/active/<consumer>.sha256`;
root-owned ssh uses `/var/lib/dev-server/active/ssh.sha256`. digests are regular
mode-`0600` files, atomically replaced. no principal owns activation proof for a
more privileged consumer. interrupted activation must remain retryable.

| change | owning consumer action |
|---|---|
| `tmux.config` | source a running server once; store the config and plugin-generation hash in its live option |
| `shell.config`, `ai.instructions` | future shells or agent sessions |
| `claude.settings` | live claude sessions reload settings and re-run the status line |
| `desktop.session` | defer to login or manual ghostty reload |
| `ssh.config` | validate, then reload ssh |
| `docker.config` | rebuild/restart only with no running containers; otherwise defer |
| `herdr.runtime` | start once when absent; changed binary/config/unit on a running server is an operator stop, then reapply; never a restart |
| `herdr.gate`, `jarvis.gate` | the next ssh connection; nothing restarts |
| `skid.unit`, `skid.runtime` | activate original skid only, with its own rollback |
| `herdr-mobile.unit`, `herdr-mobile.runtime` | activate herdr-mobile only, with its own rollback |
| `herdr.integration` | future agent sessions; nothing restarts |
| `codex.runtime` | explicit authorized drain/restart of all three services |
| `tailscale.serve` | reconcile private mapping; no tailscale restart |
| `system.reboot` | report only |

tmux activation belongs to `lib/tmux.sh` on all three hosts. package installation
precedes it; dotfiles install the config and immutable plugin generations before
reload. the live identity advances only after successful reload.
resurrect and continuum load directly in that order. the repo owns their pins
and installation; tpm's managed checkout and bindings are retired without
removing unrelated bindings, saved layouts, or running sessions.

consumer actions remain beside their subsystem. deduplicate within one run.
never infer a restart target from arbitrary processes. native package/service
scripts retain their supported behavior; report other stale sessions/services
rather than trying to restart them. temporary candidates are cleaned on exit.

## files and ai tools

exact-host desktop/hardware policy is separate from package installation.
macos homebrew owns ghostty and its font; the repo owns its configuration.
arch policy owns its declared hardware, boot, touchpad, and desktop settings.
xorg exclusively applies the touchpad declaration at display-server startup.
every apply compares the installed file's modification time with all live xorg
process starts and reports deferred activation until the file predates them.
equal-second ordering remains deferred; exited processes are not consumers.
restart the display server or reboot to activate changes. timestamp ordering
assumes normal host clock continuity and does not verify device behavior.
macos tailscale is app-store-owned; verify and optionally start the exact app,
but never install, update, replace, or sign in to it.

git plugins use exact immutable commit generations and atomic links. do not
adopt old in-place clones. cursor extension and other exact tool declarations
remain reviewable repository inputs. no generic profile/plugin framework,
compatibility state reader, or second package manager is introduced.

one codex binary is installed at `$HOME/.local/bin/codex` through npm's user
prefix. devbox apply and upgrade reconcile its declared pin, including drift
from a native update; workstation upgrade resolves one stable
`MAJOR.MINOR.PATCH` from `latest`. installation uses npm integrity with scripts
disabled. installed manifest and executable must agree; no stale-candidate
fallback after a failed requested upgrade.

one claude native binary is published at `$HOME/.local/bin/claude` from its
versioned native directory. bootstrap downloads anthropic's official https
installer to a temporary file and syntax-checks it before execution. subsequent
updates use native `install latest` under the normal host home. both accounts
share the repo-owned `latest` channel with no account version floor; reconcile
these settings before installation. the native updater owns background updates
and old-version cleanup. reject a conflicting canonical path; do not restart
running claude processes.

ordinary and herdr commands retain their established implementations:
`codex-shared.py` renders the three codex account commands from `profiles.json`;
`ai-profile` supplies only `claude-work`; bare claude resolves to its existing
native executable. normal homes remain `.codex`, `.codex-work`, `.codex-work2`,
`.claude` and `.claude-work`, with existing override and account-selection
semantics. they are shared user state, not herdr-owned or cognition-only state.
preserve authentication, configuration, history, memories, plugins and trust.

original skid's own forge and marked bash/zsh terminals select those same
accounts through scoped native commands. manual personal claude leaves
`CLAUDE_CONFIG_DIR` unset, preserving its native default state including
`~/.claude.json`. neither gateway provisions or rewrites provider homes.
ordinary and genuine herdr terminals do not load those functions.
skid apply owns startup-file validation and guarded
source installation; shared provider maintenance has no skid prerequisite.
startup symlinks retain their identity; skid edits their regular targets while
preserving unrelated content and modes. the original app owns environment
creation and removal of inherited `HERDR_*`; upstream herdr starts with no tmux
context. skid sets `SKIDBLADNIR_AGENT=1` only at provider exec; its explicitly
loaded claude plugin rejects foreign/herdr contexts before reading input or
config and still verifies process identity. skid installs no codex hooks.
the contract is in the
[runbook](docs/gateway-separation-runbook.md#provider-and-jarvis-contract).

interactive zsh aliases separately add `--yolo` for all three codex profiles
and `--dangerously-skip-permissions` for both claude profiles. `command
<profile>` bypasses an alias. original skid's forge profiles carry their own
explicit arguments and claude identity plugin; herdr-mobile keeps its reduced
provider/environment profiles and herdr's native integrations.

`assets/agent-instructions.md` supplies the five account instruction files,
installed as mode `0600`. `assets/claude/statusline.sh` is installed as
`~/bin/claude-statusline`, and both claude account `settings.json` files carry a
repo-owned `statusLine` key pointing at it. apply also sets `autoUpdatesChannel`
to `latest` and removes `minimumVersion` in both accounts. every other settings
key, authentication, history, project instructions, and skills remain user-owned.
instruction updates affect new sessions; status line updates apply live.

## shared codex services

`assets/codex/profiles.json`, schema v3, owns account homes, endpoints, binary,
and devbox principals. workstation paths are projected from that declaration;
there is no second account map or package version in it.

only the devbox runs them: three system services as `niels`, whose one client
is jarvis's cognition. it normalizes only the exact parents/sockets to
`0750`/`0660` for its intended client group; no public socket exists. macbook
and arch run none: their only consumer was codex's own discovery, and an
interactive codex without a server runs embedded. workstations keep the account
wrappers only. the devbox pins codex 0.155.1 because 0.156 publishes the socket
as a symlink into a private directory jarvis cannot reach
([issue](docs/issues/codex-daemon-socket.md)); workstations track npm `latest`.
preserve all account homes and credentials.

native discovery links the account's `app-server-control/app-server-control.sock`
to its managed endpoint. check all three before draining or changing coupled
inputs. exact links, including dangling ones, are idempotent; foreign links,
files, or sockets produce an action instead of takeover.

native codex owns reuse, embedded fallback, command support, and remote
semantics. compatible interactive launches can reuse a server; startup
overrides and unavailable servers can select embedded execution. explicit
remote requires attachment and has its own cwd/config/resume behavior. shared
tools use the server environment, not ambient calling-shell credentials.

missing services start. healthy running services retain operational inputs
unless `--restart-codex` authorizes drain/restart. changed coupled inputs require
`ACTION`/exit `2` before replacement. the flag also restarts unchanged services
to pick up a newer binary. cli-only upgrades do not change the operational
identity or trigger a restart. record active identity only after all three
services pass activity, socket permission, and connection checks. a connection
proves transport readiness, not a provider turn. never kill tmux or native history.

jarvis cognition remains a local client with its own permission policy.
worker control goes through jarvis's herdr gate on each host
([herdr gate](#herdr-gate-and-cross-host-use)); no dedicated jarvis worker
launcher remains.

## deployment identity

`dev_server_home_dir` defaults to `$HOME` and owns every deployment path.
`dev_server_fleet_label_prefix` defaults to `dev.niels` for mac launchagents.
`dev_server_gateway_port` defaults to `7341` for original skid;
`dev_server_mobile_gateway_port` defaults to `7342` for herdr-mobile. each is
fixed for a deployment's lifetime. linux service identity is the user account
and product unit; each product has its own port on every platform.

`dev_server_render_assets DIR OWNER` renders only the selected owner's plist
inside its private staged closure. the source names remain `dev.niels.*`;
installed mac labels use the configured prefix. source declaration bytes and
modes are checked before consumption. no gateway operation reads the other
product's pin, config, credentials or installed state.

for disposable qualification, use a temporary home, unique mac label prefix,
free loopback ports and stand-in provider executables. run with an empty
inherited environment, explicit `HOME` and known `PATH`; never expose a
production credential, herdr socket or provider home. before bootstrap prove
all candidate labels and ports are absent and all rendered paths stay below
the temporary root. invoke product libraries directly, without host-level
serve operations. record production service identities before and after.
only unload candidate labels and remove directories created by the probe.
never enable/disable production labels or touch default tmux resources.

installer control-flow probes use native-service stand-ins when no disposable
native service is available. those results do not qualify launchd/systemd,
provider turns, phone behavior or live coexistence. report each missing
boundary as `NOT_RUN` with its owner and blocker.

## herdr runtime

`assets/herdr/release-pin.json` is the herdr trust root: exact version, source
commit, platform urls and executable sha256 for the raw release binaries. one
server per host runs the pinned binary as `herdr server` under the development
user: a user systemd unit on arch and devbox, a launchagent `<prefix>.herdr` on
macbook whose paths hang off the deployment root. it is
login-scoped on macbook and arch; only devbox's user manager lingers. the unit
sets `HERDR_CONFIG_PATH` to the managed `~/.local/share/herdr/config.toml`
(automatic agent resume and every self-update check disabled) and
`HERDR_SOCKET_PATH` to the default-session socket `~/.config/herdr/herdr.sock`,
so a bare `herdr` in a shell attaches to the same instance. the user's own
`~/.config/herdr/config.toml`, snapshots and detection state stay upstream's.
the unit clears inherited herdr and xdg variables, sets `LANG`, and shares no
lifetime with either gateway. herdr-mobile orders after it; neither gateway
requires, binds or stops it. original skid has no herdr dependency.

`herdr_preflight` runs before any mutation and returns `ACTION`/exit `2`
without changing state for: a running server whose binary, config or unit
differs; an unmanaged default-session snapshot before the first managed
activation; agent-detection overrides or remote update state; named-session
sockets; a listener on the socket whose pid is not the service's; a loaded
service whose socket does not answer within a few seconds (launchd parks a job
whose program cannot be executed and does not retry when the file is repaired);
herdr or xdg variables in the launchd environment. the changed-inputs line names the
consequence (stopping ends every herdr terminal and its agents), the exact
supervisor stop, and says not to run bare `herdr` in between; an unmanaged
listener names its pid and `kill -TERM`; residue lines name the path to move
aside or remove. the changed-inputs case stages and verifies the new binary
before it reports, so the rerun after the stop cannot fail on a download.
`herdr_apply` stages the artifact and immutable generation first and promotes
`current`, the `~/.local/bin/herdr` link, config, unit and enablement only when
the service is absent or inactive; it records `herdr.runtime` (binary, config
and unit digests) only after the socket answers `ping` with the tested version
and the bundled codex and claude detection manifests are active. a failed
upgrade first stops the candidate and waits for the supervisor to finish
tearing it down; only then do the unit, config, pointers, snapshot and observed
enablement go back and the prior herdr restarts and verifies against the prior
generation's version. a candidate that cannot be stopped keeps its inputs; the
stage with the prior's backups is kept as `.apply.failed.*` in the share and
apply reports both. the prior's own failure to verify is reported as such,
never as a restart to retry. a failed first activation stops its own candidate, removes
the unit and only the snapshot it created, and leaves the generation
unreferenced. an unchanged apply downloads, writes and restarts nothing.
`herdr_prepare_artifact` stages the verified binary under the lock without
promotion, for pre-window staging.

herdr's native codex and claude integrations remain in the existing normal
account homes. the pinned herdr binary installs its integration only in homes
that already exist; personal claude keeps its normal unset-variable default.
herdr provisions no private provider homes and its service sets no provider
home overrides. gateway maintenance does not migrate or own provider state.

preserve native herdr integrations, user hooks/settings and discovery state.
only specifically verified obsolete skid registrations may be removed during
the coordinated cutover. codex can read `$HOME/.codex/hooks.json` as project
config when launched at home. qualify actual hook interactions there and in a
shared project at the integration boundary; provider relocation is not a fix.

herdr is never downgraded or stopped to undo a gateway change. recover each
separated gateway with its own verified inputs. do not restore an old whole
dev-server revision or adopt herdr-backed v0.8 as original skid. the first
separated release may need stop-and-repair because no prior separated release
exists. handback and recovery limits are in the cutover runbook.

## herdr gate and cross-host use

humans use herdr's own ssh transports: `herdr --remote <ssh-target>` attaches
a desktop client to another host's server, and `ssh <host> herdr <command>`
runs one api command there. api commands never start a server; the
`--remote` bridge starts `herdr server` itself when none listens, so it is
not for a window in which the supervised server is stopped. dev-server saves
no herdr machines ([issue](docs/issues/herdr-saved-machines.md)); ssh keys and
known hosts for these human edges stay the owner's.

jarvis reaches each host's herdr through an ssh forced command, never
`--machine`, whose `sh` probes and bridge a forced command would break.
`assets/herdr/herdr-gate` is installed as `~/.local/libexec/herdr-gate` (0755)
on all three hosts. it splits `SSH_ORIGINAL_COMMAND` with posix `shlex`, no
shell, and admits only the owner's "agents plus pane creation" in herdr 0.9.1's
spelling: `agent list|get|read|explain|wait|prompt|send-keys`, `agent start
--kind codex|claude`, `pane list|split|close` and `workspace list|create`, each
with the flags a client needs, options after positionals, space-separated
values. `--env` admits only `CODEX_HOME` naming `.codex`, `.codex-work` or
`.codex-work2`, or `CLAUDE_CONFIG_DIR` naming `.claude-work`, under the owner
home. personal claude retains its unset-variable default. jarvis's existing
worker map stays intact. herdr's global options (`--machine`, `--remote`, `--session`,
`--handoff`) anywhere, `--`, and everything else exit 1 with one content-free
line before herdr runs. an admitted argv is exec'd as `~/.local/bin/herdr`
with only `HOME` and `PATH`, so it reaches the default-session socket. the
gate's docstring lists what it leaves out and why. jarvis owns the
allowlist's content through its adr; a herdr pin change requalifies it.

the gate is policy hygiene, not containment. `agent start --pane`, `pane split`
and `pane close` accept any pane id, the owner's included, and prompts and
keys reach any agent; jarvis's codec starts agents only in panes it has just
created. whatever the gate admits runs with the owner account's authority.

`herdr_apply`, under the herdr apply lock, installs the gate and ensures
exactly one line in the owner's `~/.ssh/authorized_keys`:
`restrict,command="<python3> <home>/.local/libexec/herdr-gate" <jarvis-gate.pub>`,
where `<python3>` is `/opt/homebrew/bin/python3` on the macbook and
`/usr/bin/python3` on linux, never the shebang and the login shell's `PATH`.
the merge works on bytes and splits lines at `\n` only: every other line keeps
its bytes and line ending (a last line without one gains a `\n` before the
appended line), except lines whose options carry exactly this `command=` for
another key, which it removes (the old jarvis key after a devbox rebuild). the
result is written through a temporary file and rename at mode `0600`. the
committed key under other options, or an uncommitted key, is an `ACTION
herdr.gate` that leaves `authorized_keys` untouched. the lock serializes applies, not hand
edits; an edit racing an apply can be lost. on devbox that action, like any
herdr action, withholds the run's skid apply.

jarvis's side is devbox-only (`ansible/roles/jarvis_herdr`). `/etc/jarvis-herdr/`
(root:jarvis `0750`) holds `id_ed25519` (jarvis `0600`, generated once on
devbox under a temporary name and renamed, never copied off), and root:jarvis
`0640` copies of `assets/herdr/jarvis-ssh_config` and
`assets/herdr/jarvis-known_hosts`: the labels `devbox` (`niels@localhost`,
through its own gate), `macbook` and `arch` (`nnandal` over the tailnet), each
with `HostKeyAlias` its label, `IdentitiesOnly`, `BatchMode` and
`StrictHostKeyChecking yes`, and their committed ed25519 host keys. jarvis
runs `ssh -F /etc/jarvis-herdr/ssh_config <label> <shlex-joined herdr args>`;
`ProtectSystem=strict` leaves `/etc` readable. `assets/herdr/jarvis-gate.pub`
is the trust root. each apply derives the public half from the private key
(`ssh-keygen -y`) and, when it differs, `./devbox` reports `ACTION jarvis.gate`
with the line to commit; nothing later in the play depends on it, so the play
continues. an empty file means not yet committed.

a rebuilt devbox has a new host key and a new jarvis key. update the `devbox`
line of `assets/herdr/jarvis-known_hosts` and the workstations' own
`known_hosts`, recommit `jarvis-gate.pub` from the reported line, and apply
every host; the merge then revokes the old key's gate line.

## independent gateway installation

`lib/herdr-mobile.sh` and `lib/skidbladnir.sh` own their respective fixed
identities and host configuration. `lib/gateway-runtime.sh` shares the existing
artifact and activation mechanics. this is a finite two-product contract,
not a product registry or plugin deployment framework. ingress lives in
`lib/gateway-ingress.sh` and is invoked by the host entrypoints.

| identity | herdr-mobile | original skid |
| --- | --- | --- |
| repository id | `1342599607` | `1386409483` |
| final repository | `NielsdaWheelz/herdr-mobile` | `NielsdaWheelz/skidbladnir` |
| owned leaf / binary | `herdr-mobile` | `skidbladnir` |
| loopback | `127.0.0.1:7342` | `127.0.0.1:7341` |
| private serve | `:8444/v1` | `:8443/v1` |
| receipt stems | `herdr-mobile.runtime`, `herdr-mobile.unit` | `skid.runtime`, `skid.unit` |

pins under `assets/<product>/release-pin.json` name exact versions, commits,
platform archives and digests. pending declarations admit no activation.
repository identity is checked by the publishing/cutover operator before
selecting pins. existing name redirects and planned version numbers are not
release evidence. upstream owns archive/config schemas and release/device
acceptance; each admitted binary validates its own rendered host config.

herdr-mobile declares the herdr path/socket/tested version and four reduced
`{key,label,provider,environment}` profiles using the existing normal homes. original
skid declares tmux, `nativeControlPath`, absolute native provider commands,
explicit arguments, environment and foreground signatures. its separately
pinned helper and integrations belong only to skid. the original app owner's
source-qualified handoff supplies the config and native-helper contract;
authenticated native behavior remains a live qualification prerequisite.

under a per-product lock, reuse a verified artifact or download and verify its
archive digest, exact members, manifest and executable version/source. retain
independent `artifacts`, `releases`, `units`, `current` and `previous` below
the product's data root. runtime identity covers executable, catalogue,
manifest and host config. unchanged apply downloads and activates nothing.
skid generations also include their rendered shell launcher, shell initialization,
native-helper launcher and claude plugin. the original app's fleet verifier
implements the same digest contract, recorded in the
[runbook](docs/gateway-separation-runbook.md#generation-receipt-contract).
generation admission requires directory mode `0700` and a basename digest
suffix equal to the computed runtime identity for both products.
the stable helper command follows `current`, so
gateway rollback selects its matching immutable helper revision. private
helper environments remain while retained generations reference them. shared
provider authentication, history, trust and settings are user state; gateway
installation and rollback never write them.

before recording activation, verify authenticated health and the running
executable. a single atomic `<receipt>.pair` records the verified runtime/unit
association and is the rollback authority. the mandated `.runtime.sha256` and
`.unit.sha256` stems remain informational; interruption between their writes
cannot authorize a mixed pair. recovery leaves a distinct `previous` or none.
failed activation first confirms the candidate stopped, restores
the verified prior inputs and observed enablement, then verifies the restored
service. an unconfirmed stop preserves candidate inputs and recovery stage.
a failed first activation leaves its candidate inactive and unreferenced.
retention stays within the selected product's admitted generations; provider
homes and android signing material are outside it.

mint a fresh private regular mode-0600 bearer and random `mh-` handle for each
new separated installation. a private `deployment-identity` marker is created
before the first mint, allowing interrupted first installation to retry. an
unmarked namespace with old credentials or runtime state is refused; signing
files do not block a fresh separated install. preserve credentials on updates.
old herdr-backed skid
state is an operator handback prerequisite, never an original skid recovery
source. each product's operator `client.json` is private and independent.
gateway validation never inspects android signing files.

serve operations own only `/v1` on the selected port and preserve all unrelated
handlers and ports. no funnel, reset, private localapi or hostname rewriting.
on devbox, the deployment principal runs ingress preflight and mutation as
root with a system command path; gateway reconciliation remains under `niels`.
preflight must pass before runtime apply/remove, and runtime reconciliation
must succeed before ingress mutation. this grants no tailscale operator rights
to the user and changes no workstation elevation policy.
foreign handlers require operator resolution. scoped removal never stops
upstream herdr or tmux, and must preserve other products, provider state,
signing files and unrelated files. native removal/rollback qualification must
precede live use; source probes alone do not establish coexistence.

## devbox boundary

for an absent server: reject any existing named tailnet peer, create with the
steady private firewall, and wait for cloud-init to establish tailscale and the
deployment principal. enroll the unique named peer's openssh host key over the
tailnet into a private candidate. all subsequent connections check that key
strictly. promote it only after cloud-init succeeds, tailscale ssh is confirmed
disabled, and the operator key authenticates. then run ansible. neither the
cloud firewall nor ufw opens public ssh, including on failed creation. a new
server also brings a new jarvis gate key and host key; recommit both as in
[herdr gate](#herdr-gate-and-cross-host-use).

initial enrollment trusts the peer name authenticated by tailscale's control
plane; it does not cryptographically bind the peer to a hetzner server id.
the operator must keep that name unambiguous during creation. if creation stops
before trust promotion, use the hetzner console to repair cloud-init/tailscale
and verify `/etc/ssh/ssh_host_ed25519_key.pub`, then enroll the verified key
locally under `dev-server`. rerunning uses the strict existing-server path.

for an existing server: strict tailnet openssh as `dev-server-deploy`, steady
cloud firewall, ansible. never open public ssh or reset known host keys. the
only preflight mutation is repair of the exact steady hetzner firewall to close
unexpected ingress. hetzner and tailnet observations are authoritative;
there is no executable or duplicate local cloud-state file.

hetzner firewall and ufw independently deny public application/ssh ingress.
when ufw is inactive, rebuild its persisted boundary before enabling it.
validate ssh configuration before reload. keep operator `niels` unprivileged;
only the distinct deployment principal/key has ansible elevation. missing
github enrollment is a manual action, not automatic account/key mutation.

rootless docker activation identity covers package version, generated unit,
and daemon config. immediately verify zero running containers before rebuilding
or restarting; otherwise defer and do not record activation success.

provide utc time, postgresql 16, exactly qualified/held pgvector, the locked
`jarvis` account, and base ownership at `/opt/jarvis`, `/var/lib/jarvis`, and
`/etc/jarvis`. jarvis owns its release, environment, database/roles, migrations,
service, credentials, backups, and recovery. preserve those contents and nexus
state. jarvis is independent of developer rootless docker and is not an apply
postcondition.

a reviewed pgvector pin change authorizes the exact package upgrade or rollback
on apply or upgrade. refresh package metadata when the installed version differs,
then install the declared version and keep it held. qualification of application
and database compatibility remains with jarvis; no other pgvector version is a
fallback.

## verification and development

package-manager success proves the requested package operation. additional
checks prove touched service activation, gateway authenticated health/executable,
credential preservation, private serve/ssh ingress, absent bootstrap exposure,
and required host/account boundaries. report pending login, reboot, container,
and tmux activation. no separate doctor duplicates these checks.

there is no retained test suite or repository ci workflow. for each bounded code
change, verify the finding, write a temporary integration or live test, define
the change, and compare behavior before and after it. review adversarially,
remove the temporary test, and record evidence and limitations in the pr.
commit, push, merge, and clean up before starting the next slice. run syntax
and native checks appropriate to the boundary; temporary tests do not provide
ongoing regression coverage.

use the owned arch host for live arch acceptance. a service check is not a
provider model turn or device acceptance claim.

keep implementation proportional to one user and three hosts. prefer native
mechanisms and explicit subsystem contracts. add abstraction only when it
absorbs real complexity or enforces a named invariant. atomicity, credentials,
host-key continuity, private ingress, and verified skid rollback are retained.
record unresolved work in `docs/issues/`, one file per issue, and remove resolved
records. completed deployment plans and cutover instructions belong in git history.
