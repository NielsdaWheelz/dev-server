# host configuration contract

`dev-server` manages the three owned hosts: `macbook`, `arch`, and `devbox`.
its job is to install declared state, activate affected consumers, verify the
critical result, and report mutations, deferrals, or required actions.

## commands and update policy

```text
./workstation {apply|upgrade} [--restart-codex]
./devbox {apply|upgrade} [--restart-codex]
./workstation {help|--help|-h}
./devbox {help|--help|-h}
```

`apply` reconciles configuration and missing requirements. it does not seek
newer installed os packages or ai tools. repository pins remain desired state:
a changed pin is applied deliberately, including on ordinary apply.
`upgrade` updates rolling software and then applies the same configuration.
`--restart-codex` separately authorizes interruption of the three codex servers.

| owner | apply | upgrade |
|---|---|---|
| homebrew | install missing declarations without auto-update or bundle upgrades | update metadata and upgrade declared packages |
| pacman/yay | require declared packages; missing ones produce an action | full `pacman -Syu`, then declared aur packages |
| ubuntu apt | installed packages remain; missing requirements may refresh metadata | reconcile declared packages to repository candidates |
| codex/claude | verify and retain installed versions; bootstrap missing tools | resolve and install stable codex npm `latest` and native claude `latest` |
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

workstation order is native packages, dotfiles, exact-host personal policy,
ai tools/shared codex, herdr, the ingress preflight, skid, the ingress mapping,
then remaining postconditions. a herdr preflight action or apply failure stops
the run before skid; an ingress action skips skid and its mapping. linux is supported
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
keys, currently cursor's `remote.SSH.remotePlatform` and claude's `statusLine`. intentional symlinks have
explicit owners and targets; do not overwrite conflicting foreign paths.

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
| `skid.unit`, `skid.runtime` | start or activate gateway once, with rollback |
| `skid.integration` | future agents; no gateway restart |
| `codex.runtime` | explicit authorized drain/restart of all three services |
| `tailscale.serve` | reconcile private mapping; no tailscale restart |
| `system.reboot` | report only |

tmux activation belongs to `lib/tmux.sh` on all three hosts. package installation
precedes it; dotfiles install the config and immutable plugin generations before
reload. the live identity advances only after successful reload.

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
prefix. upgrade resolves one stable `MAJOR.MINOR.PATCH` from `latest` and uses
npm integrity with scripts disabled. installed manifest and executable must
agree; no stale-candidate fallback after a failed requested upgrade.

one claude native binary is published at `$HOME/.local/bin/claude` from its
versioned native directory. bootstrap downloads anthropic's official https
installer to a temporary file and syntax-checks it before execution. subsequent
updates use native `install latest` under the normal host home. reject a
conflicting canonical path; do not restart running claude processes.

human codex wrappers select only their declared account home and execute the
native binary, preserving argv, environment, cwd, and exit status. claude-work
selects its existing account. wrappers add no startup lookup or argument policy.
interactive zsh aliases separately add `--yolo` for all three codex profiles and
`--dangerously-skip-permissions` for both claude profiles. `command <profile>`
bypasses an alias.

`assets/agent-instructions.md` supplies the five account instruction files,
installed as mode `0600`. `assets/claude/statusline.sh` is installed as
`~/bin/claude-statusline`, and both claude account `settings.json` files carry a
repo-owned `statusLine` key pointing at it; every other settings key,
authentication, history, project instructions, and skills remain user-owned.
instruction updates affect new sessions; status line updates apply live.

## shared codex services

`assets/codex/profiles.json`, schema v3, owns account homes, endpoints, binary,
and devbox principals. workstation paths are projected from that declaration;
there is no second account map or package version in it.

macbook uses three launchagents; arch uses three user systemd services; devbox
uses three system services as `niels`. workstation runtime parents/sockets are
`0700`/`0600`; devbox normalizes only the exact parents/sockets to `0750`/`0660`
for its intended client group. no public socket or cross-user workstation
launcher exists. preserve all account homes and credentials.

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
worker control belongs to skid's common peer cli and target user authority;
no dedicated jarvis worker launcher remains.

## deployment identity

three variables in `lib/common.sh` name a deployment; nothing derives one from
another and there is no deployment name or registry.

| variable | default | meaning |
|---|---|---|
| `dev_server_home_dir` | `$HOME` | root of every installer-owned path: `.local/{share,state,bin}`, `.config`, `Library/LaunchAgents`, locks, artifact caches, active digests, herdr socket, config and snapshot |
| `dev_server_fleet_label_prefix` | `dev.niels` | launchd label prefix of the two fleet services, `<prefix>.herdr` and `<prefix>.skidbladnir`; codex-shared labels are not part of it |
| `dev_server_gateway_port` | `7341` | the gateway's loopback listen port; the health check and the ingress mapping read it |

the three are fixed for a deployment's life; changing one creates a new
deployment (the restore path verifies the prior unit, which may listen
elsewhere). a second deployment on one mac is these three set differently and
applied through the same library functions, units and unmodified binaries.

the four macbook assets that name them are templates: `dev.niels.herdr.plist`,
`dev.niels.skidbladnir.plist`, `host-config-macbook.json` and
`agent-hooks-macbook.json` carry `@ROOT@`, `@FLEET_LABEL_PREFIX@` and
`@GATEWAY_PORT@`. `dev_server_render_assets DIR` renders them in place inside a
private copy of `assets/` after the staged snapshot is verified, dies if any
`@[A-Z_]+@` remains, and points the libraries at that copy. source filenames
stay `dev.niels.*`; install targets are `<prefix>.*.plist`. rendering with the
defaults reproduces the production bytes. both plists set `HOME` to the root so
the launcher, the gateway's worker-directory root and herdr's snapshot and
detection caches follow it. every other asset is literal: arch and devbox units
use systemd's `%h`, and on arch and devbox deployment identity is the systemd
user account; the libraries die there if the prefix or port differ from their
defaults.

ingress is host-level, not deployment-level: one node has one tailscale `:8443`
mapping, and skid clients accept only that origin. `skidbladnir_ingress_preflight`
(returns 0, or 2 after an `ACTION`) and `skidbladnir_ingress_apply` run from
`workstation` and the devbox role around `skidbladnir_apply`; a second
deployment never calls them and is reachable only over loopback. two deliberate
ordering consequences: the mapping is reconciled after retention and outside
the skid apply lock, and with a stale mapping the ingress `ACTION`/exit `2` now
precedes declared-input, pin, protected-path and missing-tool failures.

a disposable deployment for qualification on the mac is applied through the
library entry the devbox role uses, never through `./workstation apply` (which
would also touch the codex-shared services):

```sh
mkdir -m 0700 /private/tmp/skq   # short root: unix socket paths are capped near 104 bytes
git -C <checkout> worktree add --detach /private/tmp/skq-src HEAD
# edit /private/tmp/skq-src/assets/skidbladnir/release-pin.json locally if a candidate is under test; never commit it
# env -i: a production herdr pane exports HERDR_* variables the preflight must not see; bash 4 or newer is required
env -i HOME=/private/tmp/skq PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  dev_server_home_dir=/private/tmp/skq \
  dev_server_fleet_label_prefix=dev.niels.skq dev_server_gateway_port=7351 \
  bash -c 'set -uo pipefail; cd /private/tmp/skq-src
    source lib/common.sh; source lib/herdr.sh; source lib/skidbladnir.sh
    stage=$(mktemp -d /private/tmp/skq-assets.XXXXXX); cp -Rp assets "$stage/assets"
    dev_server_render_assets "$stage/assets"
    # isolation checks here, before herdr_preflight
    output="$(set -e; if herdr_preflight macos; then herdr_apply macos; skidbladnir_apply macos; fi; finish_results macbook)"; rc=$?
    printf "%s\n" "$output"; rm -R "$stage"; exit $rc'
```

isolation checks before the first bootstrap: `launchctl print gui/UID/<prefix>.herdr`
and `.skidbladnir` fail; `lsof -nP -iTCP:<port> -sTCP:LISTEN` is empty;
`grep -rn /Users/<owner>` and `grep -rEn 'dev\.niels\.(herdr|skidbladnir)([^.a-z]|$)'`
over the rendered `herdr/` and `skidbladnir/` stage return nothing (repeat both
over the root after apply); `launchctl getenv HERDR_*`/`XDG_*` are empty; the
rendered plist `PATH` resolves no real `codex`, `claude`, `skid`, `skidbladnir`,
`herdr` or `tailscale`. only labels under the prefix are ever passed to
`launchctl`, never `enable` or `disable` (record `launchctl print-disabled
gui/UID` before and after); production pids are recorded first and compared
after. never run `pairing-invite` or the `agentcli` subcommands from the
candidate binary: their origin is production's `127.0.0.1:7341`. remove with
`launchctl bootout` of both labels, `git worktree remove`, and `rm -R` of the
root and stage. a seeded artifact directory is trusted, not verified against a
pin url; workers are stand-in executables, never real providers.

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
lifetime with the skid gateway: `skidbladnir.service` orders after it, nothing
requires, binds or stops the other.

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
upgrade stops the candidate and waits for the supervisor to finish tearing it
down, restores the unit, config, pointers, snapshot and observed enablement,
and restarts the prior herdr and verifies it against the prior generation's
version; the prior's own failure to verify is reported as such, never as a
restart to retry. a failed first activation stops its own candidate, removes
the unit and only the snapshot it created, and leaves the generation
unreferenced. an unchanged apply downloads, writes and restarts nothing.
`herdr_prepare_artifact` stages the verified binary under the lock without
promotion, for pre-window staging.

herdr is never downgraded or stopped to undo a gateway change. rolling the skid
gateway, config, unit or notifier back means checking out the last pre-pin
dev-server commit and applying it; that release's own library restores what it
needs, including the retired native-control helper still on disk (see
[retirement](docs/issues/skid-legacy-asset-retirement.md)).

## skid installation

`assets/skidbladnir/release-pin.json` is the release trust root: exact version,
source commit, platform urls, and archive sha256. accept only supported release
paths and valid schema. upstream owns packaging, product schema, release
certification, fleet operations, and device acceptance.
the pinned release's `skidbladnir validate-host-config` admits the declared host
config after artifact preparation; the installer keeps only deployment-owned
checks (home-rooted paths, the four account wrappers, permission flags, and
herdr path/socket literals equal to the unit's).

under one nonblocking lock, reuse a locally verified pinned artifact or download
and verify it. check archive digest, exact release members, manifest identity,
and executable version/source before caching the payload under
`~/.local/share/skidbladnir/artifacts/<archive-sha256>/`. reuse verifies cached
payload bytes against their recorded identity. unchanged apply needs no release
download, extraction, or payload copy.

runtime generations live at
`~/.local/share/skidbladnir/releases/<version>-<runtime-sha256>` and contain the
binary, catalogue, release manifest, and host config. a config-only change can
reuse release bytes while creating a new generation. `current` and `previous`
are atomic relative links. unit/launcher generations under `units/` retain the
prior verified activation inputs. both command links point to the current binary.

start an inactive gateway; activate once when runtime/unit identity changes.
authenticated health and the running executable must match before recording
active identity. on failed activation, stop the candidate and wait for its
teardown, restore the prior pointer, unit and observed enablement, restart, and
verify them. a failed first install leaves the service inactive and candidate
unreferenced. retain one prior healthy generation; prune older
owned generations only after success.

bearer, machine handle, and existing android signing credentials are private
regular mode-`0600` files and preserved. create bearer/machine handle only when
absent. account credentials, pairings, and agent session lifetimes survive
installation. hooks/notifier/claude integration have separate identity and do
not restart the gateway.

host configs declare codex `--yolo` and claude-work
`--dangerously-skip-permissions`, retaining the identity plugin. these arguments
affect new sessions. the host config names the managed herdr binary, socket and
tested version; both providers are observed through herdr terminal reads. the
retired native-control helper is no longer managed; its installed copies stay
only for the v0.6.0 rollback. one portable `skid-notify` writes the codex
completion bell to its controlling terminal, if any, and otherwise exits 0. provider sockets remain local.

expose only the owned private `/v1` tailscale serve mapping through supported
cli commands, from the host entry points, not from `skidbladnir_apply` (see
deployment identity). no funnel, private localapi, or hostname rewriting. a
stale mapping produces one exact recovery action. fleet invitation and client
bearer provisioning remain upstream operations.

## devbox boundary

for an absent server: reject any existing named tailnet peer, create with the
steady private firewall, and wait for cloud-init to establish tailscale and the
deployment principal. enroll the unique named peer's openssh host key over the
tailnet into a private candidate. all subsequent connections check that key
strictly. promote it only after cloud-init succeeds, tailscale ssh is confirmed
disabled, and the operator key authenticates. then run ansible. neither the
cloud firewall nor ufw opens public ssh, including on failed creation.

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
checks prove touched service activation, skid authenticated health/executable,
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
