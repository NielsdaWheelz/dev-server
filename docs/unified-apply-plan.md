# unified apply

implementation is merged. signed skid v0.24.2 passed public release verification;
the approved macbook and devbox cutovers are complete. memory activation remains
pending on both, and busy docker activation on devbox. arch is outside this
rollout. [qualification](issues/unified-apply-qualification.md) records the
remaining boundaries; this document does not authorize another live operation.

## contract

```text
./workstation apply   # this macbook or the owned arch workstation
./devbox apply        # devbox only
```

one maintenance command installs/updates declared software and configuration,
including skid, the canonical codex cli and all three existing codex account
daemons. the native updater owns activation and may interrupt work; finish
important turns first. there is no forced daemon restart, `--restart` flag,
update-pending detector or safe/full mode split.
latest means the release selected by the native updater's supported policy;
cli and daemon versions need not match. do not silently use `--from-cli`, which
copies and pins the daemon to the cli package.

skid follows the latest signed stable release. retain a reviewed bootstrap
source/checksum and the existing release-signing key, not an exact application
version pin. authentication proves the publisher, not compatibility of future
releases. retain downgrade refusal and existing platform/signing prerequisites.

claude remains the owner's explicit bootstrap/adoption exception: its known
updater activation bug is separate work. existing live cli processes also retain
their loaded code until reopened; updating the canonical executable changes new
invocations. promise neither instant replacement of every client nor completed
in-flight work.

codex maintenance does not stop/reconstruct tmux. use native daemon update and
client reconnection. managed restart documents automatic reconnect; external
update behavior needs qualification. do not infer every client survived from
daemon readiness. clients that exit use their original account wrapper with
`resume` and select the conversation; never inject resume input automatically.

stay on the official standalone installer for both cli installation and updates;
reuse the existing checked-download-then-execute wrapper. do not replace it with
npm/homebrew, a custom package layout or the inspected self-update shell pipeline.
the default upstream installer updates the cli, not separately managed daemons;
native daemon controls own that maintenance. the documented interactive
`/daemon` update exits its initiating client; this does not establish that the
external updater exits other clients.

existing skid checkpoint/restore requires proved tmux-server loss. no recovery
extension is part of this integration; first qualify native external update and
reconnection rather than constructing speculative client-relaunch machinery.

tmux/runtime activation remains separate explicit maintenance. ordinary apply
can install a new tmux binary while its running server retains the old one;
report that pending activation and exit 2. never pass `--restart-terminals`, kill
tmux or rewrite its checkpoint from host apply. runtime cutovers require separate
owner approval.

exit codes: 0 = all requested in-scope operations completed and verified;
2 = pending activation, required action or unknown completion; 1 = definite
failure; 64 = invalid invocation. native package hooks can independently restart
services/workloads. dev-server never intentionally reboots, logs out, stops busy
containers, acts on other hosts or deletes provider data. remove both `gateway apply/remove skidbladnir`
paths; standalone skid remains independently usable for repair/uninstall.

## structure and linear flow

| owner | explicit responsibility |
|---|---|
| entrypoints / ansible | target, staged closure, host packages/configuration, result transport |
| `lib/ai-tools.sh` | checked cli installer, account wrappers, native daemon maintenance |
| `lib/skidbladnir.sh` | reviewed bootstrap, ordinary signed installer, devbox-only authoritative yaml |
| skid | its runtime/gateway admission, installation, readiness and release cleanup |
| native one-shot | final activation survives its invoking codex daemon restarting |
| native installers | version selection, package layouts and supported housekeeping |

1. reject extra arguments/retired commands before host access. admit the existing
   exact target and stage one coherent input closure. precondition: one apply per
   host at a time; keep existing native package/installer locks, without adding a
   whole-host transaction coordinator.
2. run existing package/dotfile/personal-policy installation, checked codex cli
   maintenance, wrappers and memory configuration. preserve existing account
   homes, credentials, history and installer-provenance sanitation. move daemon
   activation after all configuration it consumes.
3. invoke skid's authenticated ordinary installer, without terminal restart.
   apply authoritative yaml on devbox only after the gateway can accept it. relay
   gateway readiness or runtime-activation deferral. a gateway restart is allowed
   during this maintenance command; do not add a separate no-op planner.
4. independent final activation: for `codex`, `codex-work`, `codex-work2`, in that
   order, invoke each account wrapper's native `app-server daemon start`
   (start/reuse), plain `update`, then `version`. start also bootstraps a missing
   native package; the updater owns activation. verify the running version.
   do not compare daemon versions to the cli or invent a release-selection API.
5. owners perform eligible cleanup; fold cleanup failures into the final result,
   then summarize. a deferral may coexist with completed independent work.
   a definite failure stops dependent operations; earlier changes remain.

the native updater reports restarted, already current (left running), or not
running. preserve that behavior; do not append a forced restart. update failure
stops the dependent version check and later accounts; report failed, completed
and unattempted accounts distinctly. never automatically retry a lost operation. a ready daemon
does not prove a configuration setting requiring restart has been reloaded;
report any established pending activation as action required, without silently
forcing a restart or claiming loaded configuration from files/version alone.

reuse existing snapshots, atomic file installation, locks, account wrappers,
tmux binary/server version observation and `render_result`/`finish_results`.
consumers never inspect skid's recipe, installer receipts, provider package
selection links or private service implementations. no new recovery protocol,
checkpoint-stop api, dry-run planner, hook or host package registry.

## narrow interfaces

**skid bootstrap pin:** replace the application release pin with
`assets/skidbladnir/bootstrap-pin.json`:

```text
{schemaVersion:1, sourceSha:40-lowercase-hex, installerSha256:64-lowercase-hex}
```

keep existing strict pin validation/checksum verification. the reviewed bootstrap
must embed the existing key and propagate the new installer exit 2; update its
pin with the first qualifying signed release. call it without a version to select
the upstream latest stable release once per run; the standalone
installer owns artifact verification/selection. no unreviewed bootstrap from main.

**skid exit contract:** native installer/bootstrap exit 2 means owner-rendered
action required, including refused occupied terminal-runtime replacement; 1 means
failure. add a typed owner error mapped at its cli boundary, not diagnostic-text
parsing or relabeling every installer failure. propagate status through bootstrap,
shell wrapper and ansible. occupied runtime refusal precedes terminal mutation.
current v0.24 lacks this distinction: publish that small skid change before the
dev-server cutover. no new product state, http api or recovery schema.

**native adapter:** use supported `update`, `start`, `version` commands; no
fictional `daemon status`/`update --check`. successful version output is json;
failed connection is unavailable, not proof of absence. qualify/map its actual
required fields inside the provider adapter before freezing implementation.
trust successful native maintenance only with the supported postoperation running
version/health evidence; do not claim an independently proven upstream target.
never persist whole native account reports or scrape updater prose for state.

**one-shot and result:** only final unprivileged activation needs native detachment:
launchd on macos, systemd user service on linux, no keepalive/retry/login trigger.
retain foreground interactive/elevated package work. pass no credential/password
through job arguments, reports or copied ambient environment.

copy final inputs into target-owned scratch; controller cleanup cannot remove
them. use one fixed target-local activation-job name and the existing target-side
lock primitive for activation only; no controller lock descriptor crosses ssh.
refuse a running/unfinished/unknown activation before further work. remove a
finished native registration only after its finished report is safely recorded.
before submission, transfer scratch cleanup away from the foreground trap and
write the run report. the job acknowledges ownership and acquires its activation
lock before mutations. unknown submission retains scratch/result and never
resubmits. this does not claim concurrent package/config phases are supported.

normally wait for completion. disconnected caller gets the result location and
exit 2. keep one atomic last-run report at the owner's existing state root,
`~/.local/state/dev-server/apply.json`; directories 0700, files 0600:

```text
{schemaVersion:1, run:string, target:"macbook"|"arch"|"devbox",
 state:"running"|"finished", jobAccepted:boolean, exitCode:null|0|1|2,
 results:[{status:string, subject:string, detail:string}]}
```

`run` matches the submitted job; only that job sets `jobAccepted:true` as its
ownership acknowledgement. false is not proof that submission failed; only a
definite pre-dispatch rejection permits caller cleanup. only finished has an exit
code. missing/corrupt
report, or dead job with unfinished report, means unknown; inspect actual owners
before explicit retry. the report is a result/handoff aid, never a resumption
ledger. retain unknown scratch until repair; prune completed run inputs. no
terminal bytes, prompts, objectives, credentials or provider account data.

## cleanup and content

remove eligible run-owned scratch and superseded artifacts through their owner.
skid prunes old releases after readiness; the official codex cli installer prunes
eligible standalone releases. native package managers and account-daemon updaters
own their separate housekeeping/retention. codex has no verified independent
release-prune command: do not sweep its account packages or promise zero retained
versions. full application uninstall is a separate explicit operation, outside
apply; standalone `skid uninstall` retains its drain requirement and preserves
settings/private/provider data. no provider purge, undeclared-package removal,
rollback engine or generic garbage collector.

the content designer owns each feature's copy within the existing result-row
schema. good content names outcome, evidence limit and supported next action:

| feature | required content |
|---|---|
| help | every apply updates codex daemons; native activation may interrupt work; claude exception and package-hook limit |
| daemon result | report the native outcome and observed running version; use `RESTARTED` only with restart evidence; never claim all chats continued |
| terminal deferral | `DEFERRED  tmux: new binary installed; running server activation requires explicit maintenance` |
| lost completion | `ACTION  apply: completion unknown; inspect <result-path> before retrying` |
| cleanup failure | `ERROR  skid cleanup: release active; obsolete-release removal failed` only when the owner establishes both facts |

reuse all existing statuses; controllers preserve every row, including deferred
and reloaded, without prose parsing. final summary follows cleanup; pending
activation cannot be hidden behind `updated`/exit 0. component owners render
their own diagnostics; no duplicate copy tables.

## implementation boundaries and acceptance

| slice | exclusive files |
|---|---|
| a: skid exit contract | skid `internal/install/{install.go,terminal.go}`, `cmd/skidbladnir/main.go`, `scripts/install`; release/docs owned by integrator |
| b: providers | dev-server `lib/ai-tools.sh`; native adapter, late daemon activation |
| c: orchestration | dev-server `workstation`, `devbox`, optional deep `lib/activation.sh`, `ansible/playbooks/apply.yml`, `ansible/roles/{ai_tools,memory,workspace_assets}/tasks/main.yml`; include skid library/assets and final activation inputs on target |
| d: skid consumer | dev-server `lib/skidbladnir.sh`, `lib/tmux.sh`, bootstrap pin; delete old release pin and `ansible/playbooks/gateway.yml` |
| integrator / designer | `lib/common.sh`, `SPEC.md`, `README.md`, runbook, this plan and directly affected issue records; shared results/copy/interfaces |

the slices are integrated and reviewed. remaining native boundaries are tracked in
[qualification](issues/unified-apply-qualification.md).

prove with a few disposable integration/manual runs:

1. both entrypoints perform one target-local apply; retired/extra arguments cause
   no access; latest selection and installer trust remain owner-controlled.
2. native updater activates updates and leaves current daemons alone; start/reuse
   covers stopped daemons. running version is observed; configuration activation
   is not inferred from version alone. qualify connected-client update behavior;
   tmux shutdown/reconstruction is never requested to maintain codex.
3. a new tmux/runtime activation returns 2 without shutting down occupied work;
   other failures remain 1, all remote results survive transport.
4. caller daemon loss cannot kill final activation, lose staged inputs or cause
   a second job. overlapping activation is refused; missing completion stays unknown.
5. cleanup touches only eligible owned artifacts. activation plus cleanup failure
   reports that partial outcome; no premature success summary.

use no retained behavioral suite, new gates or fleet-wide qualification program.
native/live boundaries not exercised are `not_run`, never passed. real accounts,
hosts/services and installs require current owner approval. record concrete
unresolved issues with reproduction and resolution evidence. no deployment here.

references: current `SPEC.md` and named modules; [official cli install/update
path](https://learn.chatgpt.com/docs/codex/cli); [official codex restart/update
behavior](https://learn.chatgpt.com/docs/developer-commands?surface=cli#manage-the-background-server-with-daemon);
[claude exception](issues/claude-native-update-activation.md).
