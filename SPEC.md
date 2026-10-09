# host configuration contract

`dev-server` manages the three owned hosts: `macbook`, `arch`, and `devbox`.
its job is to install declared state, activate affected consumers, verify the
critical result, and report mutations, deferrals, or required actions.

the native ai installation policy and obsolete provider retirement are complete.
[the validation record](docs/ai-native-installation-validation.md) records fleet
acceptance and cleanup.

## commands and update policy

```text
./workstation apply
./devbox apply
./workstation gateway {apply|remove} skidbladnir
./devbox gateway {apply|remove} skidbladnir
./workstation {help|--help|-h}
./devbox {help|--help|-h}
```

`apply` updates rolling host packages, bootstraps missing ai tools, reconciles
exact repository pins, and applies configuration. rolling package versions come
from upstream on each run; repository pins remain exact desired state. existing
ai installations follow their upstream update policy independently of apply.
there is no configuration-only or offline mode and no `upgrade` command or alias.

gateway operations install or remove skid without updating shared host tools.
ordinary host apply installs no gateway, herdr runtime, worker hook or ssh gate.
herdr and herdr-mobile installation and removal commands are retired. ordinary
apply never discards workers.
[the maintenance runbook](docs/gateway-separation-runbook.md) describes skid
maintenance and the root-owned retirement evidence.

| owner | apply |
|---|---|
| homebrew | update metadata and upgrade declared formulae and casks |
| pacman/yay | full `pacman -Syu` with declared packages, then declared aur packages |
| ubuntu apt | refresh metadata and reconcile declared packages to repository candidates |
| upstream tmux | latest stable release; native packages on workstations, official source build in `/usr/local` on ubuntu |
| codex/claude native installers | bootstrap missing commands; adopt working native installations without selecting or changing their versions |
| repo pins | install declared exact versions |

native package managers resolve required dependencies. arch partial upgrades
are forbidden. ubuntu unattended security updates remain independently owned
by their native service. pgvector stays exactly pinned and held. apply does not
prune undeclared packages, upgrade the distribution, recreate a vps, reboot,
log out, or kill tmux. repo-owned docker activation defers while containers
run; native package installation/upgrade scripts can still restart their
services. a host apply is not a zero-interruption guarantee. package updates
are not transactional or automatically rolled back; native package managers
own partial-install repair.

an unchanged checkout can resolve newer rolling software. already-converged
managed configuration and pinned components must be left alone, except for an
explicitly requested codex restart. unchanged ingress must stay untouched.
native package managers and installers
own metadata and maintenance bookkeeping. exit `0` means
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
policy, ai tools, then remaining postconditions. a gateway
operation stages only its own declaration closure, checks its owned ingress,
and applies/removes that gateway and handler. neither gateway operation runs
retired runtime preflight or host-tool provisioning. linux is supported
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
keys, currently cursor's `remote.SSH.remotePlatform` and claude's `statusLine`.
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
| `tmux.config` | source a running server once; store the config-only hash in its live option |
| `shell.config`, `ai.instructions` | future shells or agent sessions |
| `claude.settings` | live claude sessions reload settings and re-run the status line |
| `desktop.session` | defer to login or manual ghostty reload |
| `ssh.config` | validate, then reload ssh |
| `docker.config` | rebuild/restart only with no running containers; otherwise defer |
| `skid.unit`, `skid.runtime` | activate original skid only, with its own rollback |
| `tailscale.serve` | reconcile private mapping; no tailscale restart |
| `system.reboot` | report only |

tmux version selection and activation belong to `lib/tmux.sh` on all three hosts.
resolve the latest stable tag from the official release endpoint and verify the
installed executable against it. homebrew and pacman retain workstation package
ownership; fail apply if their candidate has not caught up. ubuntu apt supplies
build dependencies; compile the official release and atomically install the
verified binary at `/usr/local/bin/tmux`, leaving apt's `/usr/bin/tmux` untouched.
an unchanged version is not rebuilt. download, build or verification failures
must leave the installed binary intact. skid uses `/usr/local/bin/tmux` on devbox
and the native package paths on workstations; gateway apply records the installed
version. an upgrade requires gateway configuration convergence before an explicit
tmux restart. ordinary host apply continues to defer that destructive restart.

package installation precedes activation; dotfiles install the config first.
skid is the sole workspace recovery owner. resurrect and continuum are no longer installed or
loaded. activation removes exact owned script options and bindings in every
native key table, then reloads the managed status line. only complete commands
targeting their owned aliases or immutable generations are retired; foreign
options, unrelated commands and compound bindings remain untouched. dotfiles
remove only the two exact owned plugin symlinks, retaining snapshots and inert
generations. existing one-way tpm checkout and binding retirement remains.

the config sets server options `exit-empty off` and `exit-unattached off`.
activation observes populated and empty servers without starting an absent
server or replacing live work. its config-only identity advances after
successful retirement and reload; failure remains retryable. repeated apply
leaves converged state alone.

run full host apply before activating a gateway with recovery; gateway-only
operations keep their existing narrow scope. finish or stop any legacy restore
already executing during maintenance; apply does not hunt processes. recovery
reconstructs the workspace with fresh shells. agent history remains native and
the user resumes the desired conversation.

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

each host user has one canonical native command per provider:
`$HOME/.local/bin/codex` and `$HOME/.local/bin/claude`. ordinary profiles, skid's
forge, marked terminals and native helper dispatch invoke those exact paths.
the canonical commands may be upstream-managed symlinks. consumers retain the
canonical path rather than a resolved release path, npm package path or copied
executable. provider exec must remain native so skid observes the provider
process directly.

| owner | responsibility |
|---|---|
| upstream native installers | executable contents, release directories, integrity, selection, update metadata and native repair |
| dev-server ai tools | bootstrap absent commands, verify callable native providers, install account wrappers and owned configuration |
| user and upstream settings | release channels, automatic updates, manual upgrades and version selection |
| skid | use canonical provider commands and existing account homes; verify its own integration |

bootstrap uses the official standalone installers at
`https://chatgpt.com/codex/install.sh` and `https://claude.ai/install.sh`, with
their default release selection. download each requested installer to a
temporary file over https and syntax-check it before execution. run as the
host user with the normal host home. codex installation explicitly uses
`CODEX_HOME=$HOME/.codex` and `CODEX_INSTALL_DIR=$HOME/.local/bin`; claude
bootstrap leaves `CLAUDE_CONFIG_DIR` unset. inherited account selectors must
not change where a shared installation is created. keep account wrappers
ahead of the canonical commands in the managed shell path.

| canonical command state | apply behavior |
|---|---|
| absent | invoke its official native installer, then verify the native command and provider version output |
| working native provider | adopt it; invoke no provider installer, updater or release lookup |
| broken link, invalid executable or conflicting script (including npm launchers) | report `ACTION` with the concrete native repair action; preserve the conflicting path |

bootstrap failure or a failed post-install check is an error. report partial
installation and native repair; do not substitute another installation method.
adoption validates the native executable and expected provider version output,
without requiring a particular version, absolute symlink target or release
directory schema. the canonical command is the installation interface.

manual codex upgrades use the canonical command with the fixed installation
context and clear inherited npm-manager markers:
`env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_PACKAGE_ROOT
CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin"
"$HOME/.local/bin/codex" update`. upstream installation detection cannot find
the shared installation when `CODEX_HOME` selects a work account. preserve
simple profile wrappers; do not parse updater arguments or create more cli
installations. claude upgrades use `claude update`; the invoking account's
channel selects the shared version. official installer reruns use the same
installation context as bootstrap. native installers own their selection and
layout; dev-server owns neither.
an upgrade must reach every future cli launch without a dev-server edit, apply,
skid reapply or gateway restart. existing processes retain their loaded code
until upstream activation or an operator action. ordinary apply does not
restart provider sessions, update daemons, select release channels, change
auto-update settings, configure npm's prefix or enforce ai-specific node/npm
minimum versions. host package declarations still own node/npm where needed.

gateway operations require working canonical native providers and never install
or upgrade them. upgrades do not alter skid generation identity because its
configuration stores canonical command paths rather than provider versions.
upstream cli or protocol changes can still require integration maintenance;
shared paths are not a promise of compatibility with every future release.

ordinary account commands are installed by `lib/ai-tools.sh`.
`codex` preserves a nonempty `CODEX_HOME`, defaulting to `.codex`; the named
work commands force `.codex-work` or `.codex-work2`. each executes the canonical
cli with unchanged arguments. `ai-profile` supplies only `claude-work`; bare
claude resolves to its existing native executable. normal homes remain
`.codex`, `.codex-work`, `.codex-work2`,
`.claude` and `.claude-work`, with existing override and account-selection
semantics. they are shared user state.
preserve authentication, configuration, history, memories, plugins and trust.

original skid's own forge and marked bash/zsh terminals select those same
accounts through scoped native commands. manual personal claude leaves
`CLAUDE_CONFIG_DIR` unset, preserving its native default state including
`~/.claude.json`. skid never provisions or rewrites provider homes.
ordinary terminals do not load those functions.
skid apply owns startup-file validation and guarded
source installation; shared provider maintenance has no skid prerequisite.
startup symlinks retain their identity; skid edits their regular targets while
preserving unrelated content and modes. the app owns its terminal environment and provider account isolation. skid sets `SKIDBLADNIR_AGENT=1` only at provider exec; its explicitly
loaded claude plugin rejects unmarked contexts before reading input or
config and still verifies process identity. skid installs no codex hooks.

the cached zsh instant-prompt preamble is skipped only for the exact intended
skid shell with a pending startup action, excluding subshells. the
installer updates the recognized preamble in place and validates its owned
markers during preflight. unknown or duplicated instant-prompt snippets require
correction before apply. custom files without a preamble keep that policy.
ordinary dotfile apply retains the same guard; theme configuration is unchanged.
powerlevel10k may invalidate its shared cache after the skipped preamble, so a
later ordinary shell may need to warm it again. startup-file edits are outside
gateway generation rollback; the runbook owns their explicit reversal.
the contract is in the
[runbook](docs/gateway-separation-runbook.md#provider-and-jarvis-contract).

interactive zsh aliases separately add `--yolo` for all three codex profiles
and `--dangerously-skip-permissions` for both claude profiles. `command
<profile>` bypasses an alias. original skid's forge profiles carry their own
explicit arguments and claude identity plugin.

`assets/agent-instructions.md` supplies the five account instruction files,
installed as mode `0600`. `assets/claude/statusline.sh` is installed as
`~/bin/claude-statusline`, and both claude account `settings.json` files carry a
repo-owned `statusLine` key pointing at it. every other settings
key, authentication, history, project instructions, and skills remain user-owned.
instruction updates affect new sessions; status line updates apply live.
the devbox ai-tools task passes `--publish-skid-usage` to `ai_install`, which
adds that flag to both statusline commands. workstation omits it and retains
display-only statuslines. publication requires both the flag and an explicit
absolute `CLAUDE_CONFIG_DIR`; each callback atomically replaces only that
account's private `skidbladnir-usage.json`. these are devbox's saved observations,
which can be stale between callbacks; provider execution remains host-local.

## codex daemon ownership

upstream codex owns account daemon startup, discovery, reuse, command support,
and remote semantics. this repository installs no codex service, discovery
link, custom source build or daemon package policy. dev-server does not restart
agents during cli bootstrap or adoption. native update activation belongs to
upstream and the operator. preserve account homes, credentials, configuration
and history.

shared installation means one cli installation per provider per host user.
codex's account daemons may retain separate upstream-managed packages and
updaters under their existing homes. cli and running daemon versions need not
agree. dev-server does not merge those package directories, repoint their
selection links, pin them to the cli or synchronize their versions. operators
inspect and update a selected daemon through upstream commands when needed;
daemon updates can interrupt that account's work.

skid-created sessions use the upstream daemon selected by `CODEX_HOME`; its
socket is `app-server-control/app-server-control.sock` below that account home.
the host ensures the daemon is running and launches the stock tui using
`--remote unix://...`; codex owns initial thread creation. native helper control
creates and inspects explicit native conversation references independently of
terminal projection. explicit attachment uses the canonical cli with
`--remote unix://... resume THREAD_ID` and the selected account home; upstream
forbids cli permission overrides for that attachment. wrappers do not parse
arguments to conceal this restriction. manual marked-shell commands remain
ordinary stock launches without a claimed native association.

ubuntu provisions the distro's bubblewrap apparmor profile and verifies user,
network and pid namespace creation without disabling the global restriction.
earlyoom remains enabled and prefers preserving codex and claude. compare its
active arguments with the installed policy so interrupted activation is
repaired on the next apply; unchanged policy does not restart the service.
the development account's user manager uses `OOMScoreAdjust=-100`, which makes
systemd's default adjustment for its child services zero. apply activates this
without restarting user workloads and removes the former inherited +200 within
that manager's service tree, preserving other adjustments and login sessions.
linux skid gateways restart after unexpected clean exits as well as failures;
explicit service stops remain stopped.

the former shared codex runtime is retired. its service/helper/configuration
files, exact old discovery links and former client access grants are absent.
cleanup-only deployment code is deleted; apply preserves native discovery and
never stops jarvis to accommodate that removed runtime.

jarvis cognition recovery is a separate owner task, using a selected upstream
account daemon. worker deployment and herdr retirement can proceed
with jarvis stopped. this change supplies no cognition implementation or
readiness claim; jarvis activation and resume require their own acceptance.
worker control uses the fixed skid cli and private fleet configuration described below.

## deployment identity

`dev_server_home_dir` defaults to `$HOME` and owns every deployment path.
`dev_server_fleet_label_prefix` defaults to `dev.niels` for mac launchagents.
`dev_server_gateway_port` defaults to skid's `7341`, fixed for a deployment's
lifetime. linux service identity is the user account and skid unit.

`dev_server_render_assets DIR` renders only skid's plist
inside its private staged closure. the source names remain `dev.niels.*`;
installed mac labels use the configured prefix. source declaration bytes and
modes are checked before consumption. gateway operations consume only skid's pin, config, credentials and installed state.

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

## jarvis worker executable and retirement

skid gateway apply on devbox admits one artifact using the existing skid pin,
archive verifier and cache. both the gateway and `/usr/local/libexec/skidbladnir`
consume that artifact. the root cli is a regular root:root `0755` file, never a
link into the development user's home. no independent jarvis executable pin
exists.

before either executable changes, compare candidate bytes with the installed
root cli and the running gateway's `/proc/PID/exe` (or selected generation when
inactive). changed bytes, ownership or mode require `jarvis.service` to report
`ActiveState=inactive`, `Result=success`, `MainPID=0`, and exact
`/var/lib/jarvis/runtime/paused.json` state
`{"paused":true,"schema_version":"jarvis-paused.v1"}`. check this before gateway
reconciliation. the operator keeps jarvis stopped through apply; no new lock or
service lifecycle manager is introduced. identical executable apply is inert.

jarvis deployment separately installs `/etc/jarvis/agent-client.json` as a
regular jarvis:jarvis `0600` file from the existing human-provisioned fleet
configuration, with all three peers. it owns the same stopped/paused admission
for configuration changes and retains its existing service restrictions.
settings are `JARVIS_AGENT_CLI_PATH` and `JARVIS_AGENT_CLIENT_CONFIG_PATH`.
credentials are never minted for jarvis automatically. bearer rotation requires
explicit private-client redistribution before resume. gateway config changes
with unchanged executables do not pause jarvis by themselves.

the root operator completed herdr and herdr-mobile retirement on all three hosts.
owned supervisors and native servers were stopped, provider integrations and
exact ssh gate entries removed, and owned configuration, runtime, credentials,
units, commands, gates, receipts and `8444 /v1` purged and validated absent.
cleanup-only deployment code and selectors are deleted. ordinary apply neither
recreates retired products nor performs destructive retirement. preserve unrelated
settings, ssh access, serve handlers, provider accounts/history, skid workers and
permanent signing backups. there is no legacy resurrection path.

the root operator completed normal host apply and gateway apply on macbook,
devbox and arch with skid `v0.10.6` and stock codex `0.159.2`. installed personal
codex lifecycle, fleet tls, the production client under the actual jarvis uid,
and owner phone attachment passed on all three. pre-existing shared codex
app-server process lifetimes were preserved. jarvis remains disabled, inactive
and paused; activation and cognition remain separate.
[qualification](docs/gateway-separation-validation.md#2026-09-29-installed-fleet)
records the native boundaries, arch retry and deferred reboots.

installation, retirement and service containment require their own live
observations; engineering checks do not establish those boundaries.

## independent gateway installation

`lib/skidbladnir.sh` owns the fixed skid identity and host configuration;
`lib/gateway-runtime.sh` owns artifact and activation mechanics;
`lib/gateway-ingress.sh` owns only `8443 /v1`. skid's repository is
`NielsdaWheelz/skidbladnir` (repository id `1386409483`), installed leaf/binary
`skidbladnir`, loopback `127.0.0.1:7341`, receipt stems `skid.runtime` and
`skid.unit`. no retired-product configuration or cleanup code remains.

original skid also requires the public `~/.local/bin/skid` command, linked to
`../share/skidbladnir/current/skidbladnir`, like the canonical binary link.
only original's installer owns it: reject foreign paths, reconcile it on
apply, follow the verified generation during recovery, and remove it on failed
first activation or scoped removal. repairing a missing link does not change
runtime identity or require a service restart. the app owner's fleet
provisioning owns each host's private three-peer `client.json`; a working
local executable alone does not establish a usable fleet browser.

the pin under `assets/skidbladnir/release-pin.json` names exact versions, commits,
platform archives and digests. pending declarations admit no activation.
repository identity is checked by the publishing/cutover operator before
selecting pins. existing name redirects and planned version numbers are not
release evidence. upstream owns archive/config schemas and release/device
acceptance; each admitted binary validates its own rendered host config.

skid declares tmux, `nativeControlPath`, absolute native provider commands,
explicit arguments, environment and foreground signatures. its native
helper and integrations belong only to skid. the original app owner's
source-qualified handoff supplies the config and native-helper contract;
authenticated native behavior remains a live qualification prerequisite.

under skid's lock, reuse a verified artifact or download and verify its
archive digest, exact members, manifest and executable version/source. retain
independent `artifacts`, `releases`, `units`, `current` and `previous` below
skid's data root. runtime identity covers executable, catalogue,
manifest and host config. unchanged apply downloads and activates nothing.
skid generations also include their rendered shell launcher, shell and remote
context initialization, native-helper launcher and claude plugin. the original
app's fleet verifier
implements the same digest contract, recorded in the
[runbook](docs/gateway-separation-runbook.md#generation-receipt-contract).
generation admission requires directory mode `0700` and a basename digest
suffix equal to the computed runtime identity for skid.
the exact `v0.9.0` skid ten-file generation remains admissible as an upgrade
rollback target when its original source, files, modes and receipt verify.
new skid generations use the eleven-file contract.
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
retention stays within skid's admitted generations; provider
homes and android signing material are outside it.

mint a fresh private regular mode-0600 bearer and random `mh-` handle for each
new separated installation. a private `deployment-identity` marker is created
before the first mint, allowing interrupted first installation to retry. an
unmarked namespace with old credentials or runtime state is refused; signing
files do not block a fresh separated install. preserve credentials on updates.
unadmitted prior namespace state is never a recovery source. skid's operator
`client.json` remains private.
gateway validation never inspects android signing files.

serve operations own only `/v1` on the selected port and preserve all unrelated
handlers and ports. no funnel, reset, private localapi or hostname rewriting.
on devbox, the deployment principal runs ingress preflight and mutation as
root with a system command path; gateway reconciliation remains under `niels`.
preflight must pass before runtime apply/remove, and runtime reconciliation
must succeed before ingress mutation. this grants no tailscale operator rights
to the user and changes no workstation elevation policy.
foreign handlers require operator resolution. scoped removal never stops tmux
and must preserve provider state, signing files and unrelated files. qualify independent installation, failed
activation recovery and scoped removal on disposable installations before
live use. service stand-ins establish installer control flow, not native
removal. record per-host lifecycle evidence and unperformed boundaries in the runbook.
exercise recovery against an actual prior separated generation when one
exists; a first separated release has no version rollback target. do not
manufacture one or infer rollback from repeat apply.

## devbox boundary

for an absent server: reject any existing named tailnet peer, create with the
steady private firewall, and wait for cloud-init to establish tailscale and the
deployment principal. enroll the unique named peer's openssh host key over the
tailnet into a private candidate. all subsequent connections check that key
strictly. promote it only after cloud-init succeeds, tailscale ssh is confirmed
disabled, and the operator key authenticates. then run ansible. neither the
cloud firewall nor ufw opens public ssh, including on failed creation. a new
server brings a new host key; explicitly enroll its verified identity.

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
on apply. refresh package metadata, install the declared version and keep it
held. qualification of application and database compatibility remains with
jarvis; no other pgvector version is a fallback.

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

## native helper source

`assets/skid-provider/native-control.json` names the helper repository and its
entry point; nothing about it is pinned. apply installs the repository's current
default-branch revision into a revision-named generation and synchronizes its
environment with `uv sync --upgrade --extra claude-sdk --no-dev`, upgrading uv
first, so the helper takes the latest dependencies its project admits. it
verifies the revision and the claude shim, then probes the entry point and the
launcher before publishing it. isolated installation and rejected-request
probes prove packaging only; native behavior needs live qualification against
the installed stock providers.
