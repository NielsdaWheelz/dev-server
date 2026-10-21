# host configuration contract

`dev-server` manages the three owned hosts: `macbook`, `arch`, and `devbox`.
its job is to install declared state, activate affected consumers, verify the
critical result, and report mutations, deferrals, or required actions.

native ai installation and obsolete provider retirement have dated acceptance.
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

`apply` updates rolling host packages, maintains shared native codex, bootstraps
missing claude, reconciles exact repository pins, and applies configuration.
rolling package versions come from upstream on each run; repository pins remain
exact desired state. working native claude is adopted without maintenance.
there is no configuration-only or offline mode and no `upgrade` command or alias.

gateway commands delegate to standalone skid install/uninstall without updating
shared provider tools. only devbox, the authoritative hub, receives desired yaml.
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
| codex official native installer | bootstrap missing codex; maintain working native codex on every apply, then revalidate |
| claude official native installer | bootstrap missing claude; adopt working native claude; maintenance awaits the upstream activation fix |
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
keys, currently cursor's `remote.SSH.remotePlatform`, claude's `statusLine` and
`cleanupPeriodDays`, and the native `jarvis-memory` MCP server entry.
`~/.zshrc` also preserves standalone skid's existing `skidbladnir managed zsh
prompt` preamble and `skidbladnir managed shell` suffix byte-for-byte. the
`# >>> ... >>>` / `# <<< ... <<<` marker pairs must be complete, unique and at
their respective file boundaries; malformed blocks stop replacement. dev-server
owns the body between them and never creates skid's blocks or reads its receipts.
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
| `skid.config` | write authoritative hub yaml and request ordinary `skid apply` |
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
and the native package paths on workstations. skid owns detection of its tmux
installation; dev-server writes no product host-config or tested-version receipt. ordinary host apply continues to defer that destructive restart.

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
`owner_home/.local/bin/codex` and `owner_home/.local/bin/claude`. `owner_home` is
the managed host-user home, independent of the caller's runtime `HOME`.
provider dispatch executes
those exact paths. the configured skid commands explicitly select ordinary
account wrappers, whose account and memory-credential semantics remain owned by
dev-server. skid injects no account, permission or daemon arguments.
the canonical commands may be upstream-managed symlinks. consumers retain the
canonical path rather than a resolved release path, npm package path or copied
executable. provider exec must remain native so skid observes the provider
process directly.

| owner | responsibility |
|---|---|
| upstream native installers | executable contents, release directories, integrity, selection, update metadata and native repair |
| dev-server ai tools | run checked official installers for codex maintenance and missing claude; verify canonical native providers; install account wrappers and owned configuration |
| dev-server launch, admission and memory configuration owners | remove inherited installer provenance before canonical native codex execution |
| user and upstream settings | upstream release selectors, account channels, automatic updates and manual upgrades; no repository provider-version pin |
| skid | use existing account homes and the codex account wrapper, which execs the canonical command; verify its own integration |

use the unchanged official standalone installers at
`https://chatgpt.com/codex/install.sh` and `https://claude.ai/install.sh`.
download each requested script to a temporary file over https, reject empty or
invalid shell syntax, and check execution status. run as the host owner with
`HOME=owner_home`. codex runs with cwd=`owner_home` and closed stdin, and fixes
`CODEX_HOME=owner_home/.codex`, `CODEX_INSTALL_DIR=owner_home/.local/bin` and
`CODEX_NON_INTERACTIVE=1`. claude bootstrap unsets `CLAUDE_CONFIG_DIR`.
inherited work-account context must not redirect the shared installation.
keep account wrappers ahead of canonical commands in the managed shell path.

codex installer execution clears the exact five provenance keys below, fixes
`CODEX_INSTALL_DAEMON_ONLY=0`, and unsets `CODEX_INSTALL_DEFER_SELECTION`,
`CODEX_INSTALL_IF_LATEST` and `CODEX_INSTALL_IF_CURRENT`. this requests the cli
without conditional-selection shortcuts. preserve upstream release/transport
selectors, including `CODEX_RELEASE`; absent a release selector, upstream's
default is latest. upstream owns layout, integrity, selection and bookkeeping.

| canonical command state | apply behavior |
|---|---|
| absent | invoke its official native installer; revalidate canonical native command/version; report `INSTALLED` |
| working native codex | run the checked official installer even when healthy; revalidate; report `UPDATED` only for a before/after version difference, including a downgrade |
| working native claude | adopt it without installer, updater or release lookup; retain personal update policy |
| broken link, invalid executable or conflicting script (including npm launchers) | preserve the path; report concrete native repair `ACTION`, status `2`; do not maintain it |

failed download, installer execution or post-install admission is `ERROR`, status
`1`. earlier completed operations remain applied; partial upstream state may
remain. report repair; no fallback or automatic rollback. equal versions emit
no provider mutation event and prove only no observed version change, not newest.
codex maintenance needs network access and may advance the version on an
unchanged checkout; normal apply can fail. admission validates the native
executable and expected provider version output without requiring a particular
version, absolute symlink target or release
directory schema. the canonical command is the installation interface.

claude maintenance is deferred because its native updater can return success
after launcher activation fails. preserve bootstrap/adoption until the
[upstream activation contract](docs/issues/claude-native-update-activation.md)
is corrected. normal apply must not invoke a claude updater. codex's direct
`update` command can hide installer-download failure through its shell pipeline;
the [pipeline issue](docs/issues/codex-self-update-pipeline.md) explains why apply
uses the checked official script instead.

installation ownership is independent of account selection. the three owned
native invocation sites remove exactly `CODEX_MANAGED_BY_NPM`,
`CODEX_MANAGED_BY_BUN`, `CODEX_MANAGED_BY_PNPM`,
`CODEX_MANAGED_BY_VITE_PLUS` and `CODEX_MANAGED_PACKAGE_ROOT` from the child
environment, including empty and `0` values. no wildcard removal; wrappers
render the managed owner home.

| native invocation owner | preserved context and execution |
|---|---|
| account wrappers published by `ai_install_codex_profiles` in `lib/ai-tools.sh` | bare `codex` preserves nonempty `CODEX_HOME`, otherwise selects `owner_home/.codex`; work/work2 force their named homes; select only that account's memory credential and exec canonical codex with literal `"$@"` |
| codex branch of `ai_native_version` | retain fixed owner home, `.codex`, native admission and version validation; remove provenance only from the inspection child |
| codex subprocess in `assets/memory/profile-config.py` | retain private staging home, native `mcp add/remove`, owned-key validation and publication; remove provenance from its copied environment |

sanitation emits no message and changes no parent environment or running client.
claude behavior, unrelated environment, arguments and existing errors/exit status
remain unchanged. ordinary and configured skid profile launches use the same
account wrappers. skid no longer installs replacement provider functions. direct canonical invocations and external
package internals remain outside these owned boundaries.

normal workstation/devbox apply is the checked codex maintenance path.
upstream installation detection cannot find the shared installation when
`CODEX_HOME` selects a work account;
[the upstream issue](docs/issues/codex-installation-discovery.md) records that
remaining limitation. preserve simple profile wrappers; do not parse updater
arguments or create more cli installations. manual claude maintenance remains
upstream-owned and cannot promise strict activation-failure propagation; use
personal context and cwd rather than a work/project override. official installer
reruns use the same installation context as bootstrap.
a canonical selection change reaches future cli invocations without a dev-server
edit, skid reapply or gateway restart. existing processes retain their loaded code
until upstream activation or an operator action. ordinary apply does not
restart provider sessions, update account daemons, change release-channel or
auto-update settings, configure npm's prefix or enforce ai-specific node/npm
minimum versions. host package declarations still own node/npm where needed.

skid gateway commands have no provider installation prerequisite. ordinary host
apply separately owns providers, account wrappers and daemon preparation. upstream
cli/protocol changes can still need integration maintenance; shared canonical
paths are not a promise of compatibility with every future release.

`ai_install_codex_profiles` owns codex wrapper rendering/publication and the shared
memory credential helper. callers provide the existing owner home/assets context,
prepare directories and admit native codex. `ai_install_profiles` validates the
declared claude wrapper first, calls the codex owner, then publishes `claude-work` and the explicit personal claude identity plugin.
full host apply retains that composition; provider-specific publication adds no
public command or selector.

`codex` preserves a nonempty `CODEX_HOME`, defaulting to `owner_home/.codex`;
the named work commands force `owner_home/.codex-work` or
`owner_home/.codex-work2`. each executes the canonical cli with unchanged
arguments. `ai-profile` supplies only `claude-work`; bare
claude resolves to its existing native executable. normal homes remain
`.codex`, `.codex-work`, `.codex-work2`,
`.claude` and `.claude-work`, with existing override and account-selection
semantics. they are shared user state.
preserve authentication, configuration, history, memories, plugins and trust.

`assets/skidbladnir/config.yaml` preserves the four profile keys, labels and
order as personal desired state. codex commands explicitly retain `--yolo` and
each account's `--remote unix://…/app-server-control/app-server-control.sock`.
claude-work explicitly retains `--dangerously-skip-permissions` and its identity
plugin. account wrappers retain memory credentials; the plugin lives under
`~/.local/share/dev-server/claude-agent-identity` and invokes the ordinary
installed `skid agent-hook Claude SessionStart` endpoint. no deleted
provider-command shim remains in any command. metadata homes support observation;
the command alone selects execution settings.

interactive zsh aliases independently retain their ordinary permission flags.
skid owns generic shell startup integration. dev-server no longer ships copied
shell-init/terminal-context code or injects provider aliases into skid shells.
provider settings and hooks remain personal configuration, not skid prerequisites.

`assets/agent-instructions.md` supplies the five account instruction files,
installed as mode `0600`. `assets/claude/statusline.sh` is installed as
`~/bin/claude-statusline`, and both claude account `settings.json` files carry a
repo-owned `statusLine` key pointing at it. `cleanupPeriodDays` is globally
36,500 days on both claude homes, before any memory activation. this retains
other claude application data too; disk consumption is the deliberate cost.
every other settings
key, authentication, history, project instructions, and skills remain user-owned.
instruction updates affect new sessions; status line updates apply live.
every host invokes `ai_install` without arguments and installs the same
display-only statusline command. the formatter reads claude's structured stdin
and renders context usage plus optional 5-hour/weekly used quota. it owns no
quota file or publication. skid owns passive terminal observation and disclosure;
displayed figures do not establish backend freshness or reset times.

## universal memory host configuration

jarvis hosts the single archive/tree/view/search library and private memory
server. dev-server owns its host configuration, not another server, corpus,
database, collector state store or inference service. the accepted product
contract is jarvis's `docs/universal-memory.md`; jarvis's public `MemoryConfig`
validator owns admission and sharing semantics.

the declaration contains the fifteen native `(machine, account)` lanes and
`(devbox, jarvis)`. one common recipient/processor declaration governs recorded
controller sharing authorizations. admission and connection are independent;
unresolved controllers, authorizations and client identities remain disabled.
the checked-in declaration denies every lane. nexus application access is a
separate consumer handoff: native developer profiles do not grant nexus chats
access or capture nexus conversations.

the optional `nexus-owner` backend client is separate from those sixteen lanes.
the same declaration names its configured viewer UUID, controller/authorization,
independent connection and note admission, and complete Nexus model processor
labels. rendering writes `nexus/client.json` with Nexus's closed owned-absence
encoding: `{kind:"Absent"}` when disconnected/undeclared, otherwise
`{kind:"Present",value:{client,owner_user_id,mcp_url,bearer,connect,admit,processors}}`.
its credential belongs only to the Nexus backend; no native host receives it.
Nexus owns installing that private file and selecting owner-chat grants. no
automatic application conversation capture or automated-helper permission is
implied. stopped sharing changes and explicit `client:nexus-owner` rotation use
the existing declaration and one credential source.

`scripts/memory-config.py` renders one private deployment bundle from the
operator's declaration and existing credentials, using the pinned jarvis
package's public validators. the first explicit rendering mints missing random
256-bit `jmem_` capture/client bearers; later rendering preserves them. rotation
is explicit. secrets and generated bundles live under ignored `secrets/memory/`,
never checked-in assets. the server declaration contains only sha-256 hashes.
configuration changes use jarvis's stopped maintenance boundary; an ordinary
host apply cannot establish controller permission or rotate credentials.

ordinary apply consumes the rendered host bundle when supplied, installing one
collector as the owner: launchd on macbook, systemd user units on arch/devbox.
the collector uses the exact central jarvis source revision and locked
dependencies. preparing a new collector release requires ordinary contents-read
git authorization to the private universal-memory repository under the owner
account. that build credential is never copied into the deployment bundle,
collector environment or native profiles. dependency preparation fails before
profile/service changes and removes its newly owned incomplete candidate.
it sweeps every thirty seconds without overlap, has no inference
or database credentials, and keeps progress in central postgres. an absent
bundle or pending release records an action; neither activates collection.
ordinary convergence preserves credentials and leaves a matching active
collector alone. changed collector inputs restart only this collector; failed
activation leaves its active digest unchanged.

connected profiles receive their own bearer environment variable and the native
`jarvis-memory` streamable-http entry at the one declared `/v1/mcp` endpoint.
native configuration owners preserve unrelated parser-backed settings. the
shared shell environment and native helper/provider launchers load the private
client environment for future launches. existing native sessions and account
daemons are not restarted; connection acceptance must be verified separately
before claiming those existing consumers loaded the change. each connected
profile receives exactly the product's owner-authored memory instruction; tool
authority notices remain server-owned.

on devbox, memory owns only HTTPS 443 `/v1` in tailscale serve, forwarding to
`http://127.0.0.1:8768/v1`. reuse the existing serve inspector/mutator, reject
funnel or a foreign handler, and preserve every other port/path. the privileged
deployment principal owns that mutation. jarvis's listener and postgres remain
loopback-only. jarvis deployment owns the server declaration at
`/etc/jarvis/memory.json`, service maintenance and source cutover. configuring
these files is source delivery; fleet installation, actual authorization and
production activation retain their own qualification.

## codex daemon ownership

upstream codex owns account daemon startup, discovery, reuse, command support,
and remote semantics. this repository installs no codex service, discovery
link, custom source build or daemon package policy. dev-server does not restart
agents during cli bootstrap, maintenance or adoption. native update activation
belongs to upstream and the operator. preserve account homes, credentials,
configuration and history.

shared installation means one cli installation per provider per host user.
codex's account daemons may retain separate upstream-managed packages and
updaters under their existing homes. cli and running daemon versions need not
agree. dev-server does not merge those package directories, repoint their
selection links, pin them to the cli or synchronize their versions. operators
inspect and update a selected daemon through upstream commands when needed;
daemon updates can interrupt that account's work.

skid-created sessions use the upstream daemon selected by `CODEX_HOME`; its
socket is `app-server-control/app-server-control.sock` below that account home.
ordinary AI apply invokes each account wrapper with `app-server daemon start`,
using upstream start/reuse semantics and never restart/upgrade. launch commands
then use
`--remote unix://...`; codex owns initial thread creation. native helper control
creates and inspects explicit native conversation references independently of
terminal projection. explicit attachment uses the canonical cli with
`--remote unix://... resume THREAD_ID` and the selected account home; upstream
forbids cli permission overrides for that attachment. wrappers do not parse
arguments to conceal this restriction. manual account commands remain ordinary stock launches without an inferred
native association. a failed daemon start reports action and preserves existing
processes; skid neither retries that lifecycle nor starts a daemon.

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
worker control uses the matching skid cli and live installed state described below.

## deployment identity

`dev_server_home_dir` defaults to `$HOME`; shared provider and dotfile paths stay
owned by that host user. skid's installer owns its xdg paths, services, dependency
validation, shell integration and private tailscale routes. dev-server supplies
no service labels, ports, bearer, generated fleet roster or product host config.
`dev_server_render_assets DIR` only fixes the staged asset root; each owner
renders its own declarations. source bytes/modes remain coherent before use.

## jarvis worker executable and retirement

jarvis source consumes `JARVIS_AGENT_CLI_PATH` and
`JARVIS_AGENT_STATE_DIRECTORY`; skid validates the enrolled computer's live state.
there is no copied three-peer client-json reader or gateway-owned root cli
installer. jarvis retains exact-target/uncertain-write contracts and its personal
machine/profile enums. its service runs as `jarvis` with `ProtectHome=true` and
`NoNewPrivileges=true`, so it cannot directly read `niels`'s `0700`/`0600` installed
state. installed jarvis worker cutover is BLOCKED pending its separately recorded
service-state integration. no new privilege bridge or global user change belongs
in this provisioner cutover. the old release must settle its unfinished actions
before the schema change; matching code, cli and state require paused/stopped
qualification before activation.

herdr and herdr-mobile retirement is complete; cleanup-only code is deleted.
ordinary apply does not discard workers or recreate retired products. preserve
unrelated settings, ssh access, serve handlers, native accounts/history and
permanent signing backups. dated evidence remains in
[the validation record](docs/gateway-separation-validation.md).

## independent gateway installation

`lib/skidbladnir.sh` is a personal consumer of ordinary standalone skid.
`assets/skidbladnir/release-pin.json` admits one exact release version plus the
reviewed source commit and sha256 of its public `scripts/install` bootstrap.
bootstrap downloads that immutable script over https, checks its pinned hash,
then invokes it with the pinned version. skid verifies signed host archives and
owns dependency handling, installation and removal. the same reviewed bootstrap handles fresh installs and upgrades. dev-server
does not decode product receipts,
copy binaries, install helper environments or own runtime/service assets.

the explicit `awaiting-standalone-skid-release` pin blocks apply with action
before installation/configuration changes. it must become a reviewed published
pin before cutover; v0.18's old-wire archive cannot be used for this target.

only devbox receives `assets/skidbladnir/config.yaml` at its authoritative xdg
configuration path, followed by `skid apply`. macbook/arch consume the ordinary
installer and enrolled state; they receive no copied desired yaml. membership,
order and stable machine handles belong to explicit skid enrollment/conversion,
never a second roster here. omit shell to retain each host's login shell, and
omit desktop default to retain self-selection. macbook keeps ghostty notification
handling. hub placement is devbox.

when present, `${XDG_CONFIG_HOME:-~/.config}/dev-server/skidbladnir.yaml`
replaces that committed source as the complete desired hub yaml. it is a
host-owned private file, mode `0600`, retained outside git. apply copies the
whole file; no yaml merge or fallback from an invalid present file occurs.
optional firebase public options may live there; service-account private key
bytes remain in the separately configured private file.

normal upgrades preserve skid/private state and provider data. `gateway remove`
delegates to `skid uninstall`, retaining settings/private state, tmux, providers
and shared packages according to the product contract. there is no ntfy branch,
legacy reader, generation rollback implementation or automatic conversion here.
the root cutover preserves observer/device continuity and updates matching phone
and host releases only after review. installed cutover is separate from source
checks. no live apply, service operation, tmux/phone experiment or package update
is implied by this source implementation.

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
host-key continuity, private ingress, and standalone signed skid installation are retained.
record unresolved work in `docs/issues/`, one file per issue, and remove resolved
records. completed deployment plans and cutover instructions belong in git history.

## native helper source

skid's signed host release owns its native helper and locked dependencies.
dev-server installs no helper checkout, source pin, shim or runtime environment.
provider installation/accounts/settings/daemon lifecycle remain independent
personal host responsibilities.
