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
ai tools/shared codex, skid, then remaining postconditions. linux is supported
only on the exact owned arch host. arch elevation uses `ARCH_PASS` through
askpass, including yay; values come from the environment or literal ignored
repo `.env`, never evaluation. validate credentials before host changes.

ansible owns ubuntu packages, privileged configuration, and native handlers.
it consumes the staged controller closure and reports real changes. native
package managers own resolution and partial-install repair; there is no package
rollback layer.

`lib/common.sh` owns atomic file installation, hashes, typed changes, and result
rendering. it does not own package policy, service names, product schemas, or a
workflow engine. product configuration semantics belong to the product;
deployment declarations own host paths, pins, identities, and launch arguments.

## durable writes and activation

managed files use compare-before-write and same-filesystem atomic promotion.
verify bytes and mode before rename; preserve credentials and account state.
a managed file is entirely repo-owned except explicitly named parser-backed
keys, currently cursor's `remote.SSH.remotePlatform`. intentional symlinks have
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
| `desktop.session` | defer to login or manual ghostty reload |
| `ssh.config` | validate, then reload ssh |
| `docker.config` | rebuild/restart only with no running containers; otherwise defer |
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
installed as mode `0600`. authentication, settings, history, project
instructions, and skills remain user-owned. updates affect new sessions.

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
services pass verification. never kill tmux or native history.

jarvis cognition remains a local client with its own permission policy.
worker control belongs to skid's common peer cli and target user authority;
no dedicated jarvis worker launcher remains.

## skid installation

`assets/skidbladnir/release-pin.json` is the release trust root: exact version,
source commit, platform urls, and archive sha256. accept only supported release
paths and valid schema. upstream owns packaging, product schema, release
certification, fleet operations, and device acceptance.
the pinned release has no standalone read-only host-config validator, so local
admission checks remain until [that upstream gap is closed](docs/issues/skid-config-validation.md).

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
active identity. on failed activation, restore the prior pointer and unit,
restart, and verify them. a failed first install leaves the service inactive
and candidate unreferenced. retain one prior healthy generation; prune older
owned generations only after success.

bearer, machine handle, and existing android signing credentials are private
regular mode-`0600` files and preserved. create bearer/machine handle only when
absent. account credentials, pairings, and agent session lifetimes survive
installation. hooks/notifier/claude integration have separate identity and do
not restart the gateway.

host configs declare codex `--yolo` and claude-work
`--dangerously-skip-permissions`, retaining the identity plugin. these arguments
affect new sessions. native-control source and frozen provider environment are
separately pinned. provider sockets remain local.

expose only the owned private `/v1` tailscale serve mapping through supported
cli commands. no funnel, private localapi, or hostname rewriting. a stale
mapping produces one exact recovery action. fleet invitation and client bearer
provisioning remain upstream operations.

## devbox boundary

for an absent server: create, open operator `/32` bootstrap ssh, establish
cloud-init/tailscale and the deployment principal, enroll the host key over the
tailnet, close temporary ingress on success or failure, then run ansible.

for an existing server: strict tailnet openssh as `dev-server-deploy`, steady
cloud firewall, ansible. never open public ssh or reset known host keys. the
only preflight mutation is repair of the exact steady hetzner firewall to close
interrupted bootstrap exposure. hetzner and tailnet observations are authoritative;
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

## verification and development

package-manager success proves the requested package operation. additional
checks prove touched service activation, skid authenticated health/executable,
credential preservation, private serve/ssh ingress, absent bootstrap exposure,
and required host/account boundaries. report pending login, reboot, container,
and tmux activation. no separate doctor duplicates these checks.

there are no automated tests or ci checks in this checkout. verify changes
directly and record the result until [the replacement](docs/issues/test-system-rebuild.md).
use the owned arch host for live arch acceptance. a service check is not a
provider model turn or device acceptance claim.

keep implementation proportional to one user and three hosts. prefer native
mechanisms and explicit subsystem contracts. add abstraction only when it
absorbs real complexity or enforces a named invariant. atomicity, credentials,
host-key continuity, private ingress, and verified skid rollback are retained.
record unresolved work in `docs/issues/`, one file per issue, and remove resolved
records. completed deployment plans and cutover instructions belong in git history.
