# codex native launch specification and implementation plan

2026-10-13. implemented and deployed on macbook, arch and devbox from source
`b9407c431cd9e85401958cf9acff3c5efd34d767`. the
[dated acceptance record](ai-native-installation-validation.md#2026-10-13-native-launch-provenance)
qualifies the results and preservation limits. upstream proposal only, with no
fork or release dependency.

## target and contract

every dev-server-owned canonical native codex invocation removes inherited
installer provenance. installation ownership and account selection are separate.
upstream owns the canonical executable, release selection and updates.

remove exactly `CODEX_MANAGED_BY_NPM`, `CODEX_MANAGED_BY_BUN`,
`CODEX_MANAGED_BY_PNPM`, `CODEX_MANAGED_BY_VITE_PLUS` and
`CODEX_MANAGED_PACKAGE_ROOT`, including empty and `0` values.
[the inspected resolver](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/install-context/src/lib.rs#L120)
establishes this finite list; no wildcard policy.

`owner_home` means the existing rendered host-user home, independent of the
caller's runtime `HOME`. execution retains `owner_home/.local/bin/codex`,
never a resolved release path.

| boundary | required context and behavior |
|---|---|
| ordinary `codex` | preserve nonempty `CODEX_HOME`; otherwise `owner_home/.codex`; native exec with literal `"$@"` |
| ordinary work/work2 wrappers | force their existing named account homes; same exec contract |
| skid profile and fresh daemon launches | existing profile selects home; account wrapper selects memory credential and execs canonical codex |
| scoped commands in marked bash/zsh | personal → `.codex`; work/work2 → named homes; direct native exec with existing `--yolo` prefix and literal caller suffix |
| codex version admission | retain fixed owner context, native-header checks and version validation |
| memory configuration writer | retain private staging home, native `mcp add/remove`, validation and atomic publication |

remove provenance immediately before native execution: explicit `unset` in
wrappers, child-only `env -u` for version inspection, removal from the python
writer's copied environment. preserve memory selection, unrelated environment,
parent processes, claude behavior and existing exit/errors, including scoped
invalid-account status `64`. emit no sanitation message.

no command, parser, host-config field, state store, public api or schema is added.
direct canonical invocations and external package internals are outside this
owned boundary.

## structure and non-overlapping ownership

composition remains ordinary/skid profile → account wrapper → canonical codex,
and marked shell → scoped command → canonical codex. their selection rules
differ; scoped commands must not route through ordinary wrappers.

| owner | exclusive files | change |
|---|---|---|
| a, shell | `lib/ai-tools.sh` | generated account wrappers, codex version inspection and provider-specific publication ownership |
| b, scoped launch | `assets/skid-provider/provider-command` | one codex exec epilogue, explicit personal/work mapping and provenance removal; claude unchanged |
| c, configuration | `assets/memory/profile-config.py` | remove provenance from copied codex subprocess environment |
| d, content designer | `SPEC.md`, `README.md`, runbook, validation and issue docs below | current contract, maintenance command, evidence and limitation |
| e, acceptance author | temporary fixture files and disposable skid checkout's `cmd/skidbladnir` test | red/green/live acceptance; no production edits |
| integrator; read-only reviewers | this plan; integration of completed slices | boundary agreement, adversarial verification and cutover |

a–c work independently after the same red baseline; d owns docs. reuse
`ai_install_codex_profiles`, `ai_native_version`, `skidbladnir_render_configs`,
`install_managed_file`, memory staging and gateway admission.

`ai_install_codex_profiles()` owns the existing codex renderer and three-wrapper
publication, including the shared credential helper. it needs the existing owner
home/assets context and prepared directories; native admission remains the caller's
responsibility. `ai_install_profiles()` validates the claude asset first, calls
that owner, then publishes claude-work. full host apply keeps its contract; this
internal split lets the codex correction preserve installed claude bytes even when
they differ from the current declaration. no public selector or alternate asset.

tradeoff: four short explicit removal sites avoid a shared runtime helper's
deployment/version coupling. review their exact key agreement. add no library,
registry, test seam or production configuration for testing.

## content and maintenance

the designer defines good content for each feature: launch documentation names
the boundary, selector, keys, argument contract and observed result; maintenance
documentation names the command, installation owner and remaining discovery
limitation. distinguish future launches from already-running clients.

reuse contract tables, runbook commands, issue fields and
`boundary | result and scope` validation rows. add no product ui or schema.

current strict maintenance is normal apply from the accepted source, using the
checked official-installer runner described below. the initial launch rollout
qualified native `codex update` in fixed personal context; subsequent review
found its [download failure propagation defect](issues/codex-self-update-pipeline.md).
that command is no longer the recommended strict maintenance path.

update current guidance in spec, readme and
`docs/gateway-separation-runbook.md` together. remove only obsolete npm
migration/launcher-restoration paragraphs and their readme pointer; preserve
native repair and deliberate admitted rollback.

append dated acceptance to `docs/ai-native-installation-validation.md`; preserve
historical evidence. the resolved local marker-inheritance issue is removed;
retain [the upstream issue](issues/codex-installation-discovery.md).

## acceptance and implementation sequence

1. **review.** architecture, acceptance and content reviewers challenge each
   contract, test isolation and claimed result. resolve blockers before tests/code.
2. **red.** one temporary driver exercises actual generated/rendered entry points
   against original source. a compiled native receiver observes leaked provenance;
   released codex's diagnostic selects npm for an npm-marked personal launch.
   clean account/argument controls already pass. setup failure is not the red case.
3. **green.** implement a–c. independently test each key with empty, `0` and `1`
   at each owner; sweep every route with all keys present. verify key absence,
   personal default/empty/custom/alternate-home behavior, forced work homes,
   selected synthetic memory bearer, literal empty/quoted/newline/metacharacter
   arguments and existing prefixes. verify wrapper exec pid/exit behavior,
   unchanged parent/claude behavior, native admission and staged configuration.
   avoid a full Cartesian suite.
   codex-only publication preserves an installed conflicting claude wrapper and
   the current shared helper; repetition is inert. it works without a claude
   declaration. full-profile publication still requires that declaration before
   publishing anything and retains its existing claude installation contract.
4. **real native acceptance.** use genuine released codex in a disposable install.
   parse `codex doctor --json`; require both `installation` and `updates.status`
   rows, independent of overall exit/network warnings. corrected personal routing
   says `update action: standalone installer`; work/custom homes select no manager,
   with `manual or unknown` valid. use actual `profile-config.py` with genuine
   codex for successful `mcp add/remove` and preservation of unrelated settings.
   perform one disposable older→newer native upgrade using the maintenance command;
   verify canonical-link advancement and fixture account preservation. receiver
   observations and `--version` cannot prove these behaviors.
5. **live composition.** one test-owned dirty tmux server survives red→green on a
   unique `-L` socket. real http handler → tmux → bash/zsh startup/launchers →
   genuine disposable codex must produce clean new children while the server's
   pid/environment stay unchanged. public codex creation requires real fixture
   daemon preparation. direct `agent-exec` or a receiver qualifies a narrower
   boundary, never the full path.
6. **refactor.** adversarially review each slice and composition for bypasses,
   account drift, false passes and needless coupling. refactor within owned files;
   rerun affected acceptance.
7. **cut over, record, delete.** after final refactor green and selected fleet
   acceptance, retain revisions, versions/platforms, red/green/live evidence and
   cleanup scope. delete all temporary tests/drivers/receivers/accounts and owned
   resources. run focused shell/python syntax, shell lint and `git diff --check`.
   retain no suite.

fixtures start from an allowlisted environment and synthetic credentials.
an empty `HOME` alone does not exclude inherited credentials. no production
update menu is accepted, and no real prompt/token/terminal content is recorded.

live recipe: temporary test in `cmd/skidbladnir` of a disposable admitted-source
checkout. `TestMain` dispatches `terminal-exec`/`agent-exec` through existing
`run`, otherwise `m.Run()`; tmux invokes `os.Executable()`. compose actual
rendered config, existing workdir/machine/auth services, `sessions.New` with
`sessions.Config.SocketName`, `agentcontrol.New` and `gateway.New`. use
`httptest.NewServer`, its client, fixture bearer/machine headers and public
creation/text endpoints. source actual shell assets. `TMUX_TMPDIR` alone is
invalid isolation: gateway startup clears it. the outer owner retains the server;
tests delete only their created sessions.

tmux/live execution requires current-turn approval under
[skid's guardrails](../../skidbladnir/AGENTS.md). an unavailable check is
`NOT_RUN`, with owner/blocker recorded, never a pass. fixture composition does
not qualify deployed service startup, recovery, production client configuration
or phone transport. preserve existing unrelated issue records.

## cutover and limits

roll out macbook, arch and devbox; preserve running clients. from one frozen source
revision, compose `ai_native_version` and `ai_install_codex_profiles` owners to
publish ordinary codex wrappers, then use normal gateway apply for scoped assets.
atomically replace changed applying-source files on devbox. use an isolated source
worktree on arch. gateway-only apply cannot install wrappers. verify installed
paths and fresh ordinary/scoped/profile launches on each host. version admission
and memory writing execute from applying source, with no persistent writer artifact.

tradeoff: full host apply upgrades unrelated rolling software and cannot promise
client preservation. this bounded operator composition avoids those changes; it
adds no public maintenance mode. gateway activation may interrupt http/websocket
connections while retaining provider processes and tmux servers. gateway-owned
attachment clients follow the gateway's lifetime and reconnect. capture worker
pids, start times and commands before activation; verify afterward. retain strict
all-process comparison failures and qualify attachment replacement separately.
record the external native helper
revision before/after apply and qualify the deployed revision if it advances.

account files with runtime state can change while clients run. compare whole
hashes across the activation interval and an explicit identity/update/mcp field
projection. an earlier unexplained whole-hash change stays unclassified; later
matching fields cannot prove its cause or erase it. never restore account data
to manufacture preservation.

hard replacement means no opt-in, alternate launcher, compatibility branch or npm
fallback. source deployment may activate a new gateway generation; preserve tmux
workers and running provider clients. no provider
upgrade is required. future upstream upgrades retain the canonical-path contract.

routine applies now use branch `fix/codex-native-launch` in these accepted
worktrees; the macbook checkout also controls devbox:

| applying owner | source worktree | normal apply from that directory |
|---|---|---|
| macbook; devbox controller | `/Users/nnandal/Documents/code/dev-server-codex-native-launch` | `./workstation apply`; `./devbox apply` |
| arch | `/home/nnandal/Projects/dev-server-codex-native-launch` | `./workstation apply` |

the original dirty main checkout is preserved and is no longer the applying
source for this rollout. applying its old revision would reinstall the defect.
source integration into main is outside the requested branch/worktree scope.

deliberate operator rollback may restore the prior admitted generation; it also
restores the known provenance defect. do not report that state as repaired.
already-running clients retain old environments until individually relaunched.

tradeoffs: work-profile self-update remains limited upstream; explicit maintenance
selects the installation context. deleting temporary tests leaves no automatic
regression protection. [the upstream proposal](issues/codex-installation-discovery.md)
separates installation discovery from account identity and validates shim
provenance against the executable; it has no local release dependency.

non-goals: upstream code/PR, fork, installer migration, extra installations,
account consolidation, auto-update changes, global environment reset, daemon/socket
redesign, gateway binary release, phone acceptance or unrelated cleanup.

## authorized follow-up: native cli maintenance during apply

2026-10-13. normal workstation/devbox apply must maintain shared native codex.
the user initially authorized both providers, then explicitly chose strict codex
maintenance with claude deferred after its activation defect was reproduced.
this supersedes codex's bootstrap/adoption-only policy. claude retains it;
gateway scope stays unchanged. retain the branch, native ownership and account
launch contracts.

| canonical state | required operation and result |
|---|---|
| absent | existing official installer; native revalidation; `INSTALLED` |
| valid native codex | checked official installer in owner personal context; native revalidation; `UPDATED` only when the version changes; otherwise `UP TO DATE` |
| valid native claude | adopt without download or updater; unchanged existing behavior |
| broken link, script or invalid native version | preserve that provider's path; concrete `ACTION`, status `2`; no maintenance for that provider |
| failed download, updater or post-maintenance admission | visible error, status `1`; no fallback or automatic rollback |

codex uses the existing checked official-installer runner every apply. its native
`update` command's shell pipeline can hide a failed installer download. keep
`HOME=owner_home`, `CODEX_HOME=owner_home/.codex`,
`CODEX_INSTALL_DIR=owner_home/.local/bin`, noninteractive operation and the exact
five-key removal. pin `CODEX_INSTALL_DAEMON_ONLY=0`; unset
`CODEX_INSTALL_DEFER_SELECTION`, `CODEX_INSTALL_IF_LATEST` and
`CODEX_INSTALL_IF_CURRENT` so explicit cli maintenance cannot select a daemon or
silently take a conditional-update path. preserve upstream release/transport
selectors; no repository version pin.

missing claude still uses its official installer; healthy claude is adopted.
genuine claude maintenance can report success
after launcher activation fails. the [upstream activation issue](issues/claude-native-update-activation.md)
records the red evidence. no healthy claude updater path, flag or fallback is
introduced. unchanged codex means no observed version change; it does not prove
the newest release is installed. upstream release selection may downgrade.

provider operations are sequential. a completed codex update remains if later
claude admission fails; rerunning is repair. preserve running providers, account data and separate daemon
ownership. installer-owned selection/bookkeeping may change. no provider restart,
daemon update, new public command, policy registry or receipt machinery.

ownership: shell author changes only `lib/ai-tools.sh`; the acceptance author owns
temporary compiled integration/codex fixtures; the content designer owns genuine
claude blocker fixtures and the four current docs; root owns this plan, issues,
independent verification and rollout. write red against frozen `0df1b89`, then
code, green, adversarial review/refactor, genuine disposable codex
update/no-op/error qualification,
and the existing result-carrier checks. record before deleting all temporary
tests/resources. deploy applying source on all three hosts without a full rolling
host upgrade; keep the original dirty checkout intact.
