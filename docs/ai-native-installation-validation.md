# native ai installation validation

2026-10-02. pr #155 merged as `01d69dbf2faad9884e60b96192e6f87ed28f5177`;
that implementation is deployed on all three hosts. source, disposable
qualification, installed-fleet native acceptance and obsolete provider cleanup
passed. obsolete npm provider packages and unselected shared native cli releases
are removed.
this record separates actual native behavior from compiled-provider probes.

## source contract

`lib/ai-tools.sh` bootstraps absent canonical commands using official native
installers, then checks native executable and provider version output. existing
native commands are adopted without release lookup, installer or updater. broken
links, scripts and invalid commands remain untouched and return action `2`.
no npm manifest, provider version comparison, npm prefix mutation or ai-specific
node/npm gate remains. host package declarations retain their other consumers.

`lib/skid-provider.sh` shares that check and returns canonical command paths.
existing rendering and account selection need no additional mechanism. no
consumer stores an installer release path. ansible carries the ai result to the
controller as a temporary `rc`/`stdout` json file, preserving action `2` and
literal paths independently of callback formatting.

temporary compiled-native probes passed: missing installations, installer
failure and invalid post-install output; offline adoption with download/npm
commands rejecting calls; regular executables and relative/chained symlinks;
prerelease/build versions; script rejection before execution; preserved broken
links and conflicts; both shared-entry-point action returns. 50 wrapper,
rendered forge, bash/zsh marked and claude-helper launches preserved literal
arguments, account selectors, personal overrides and plugin arguments across
canonical symlink replacement with unchanged configuration bytes.

actual local ansible role/controller probes passed adoption `0`, action `2`
with quotes/backslashes preserved, and installer failure `1`. bash/zsh syntax,
shellcheck and ansible apply/gateway syntax passed. probes are temporary; no
retained test suite or new dependency was introduced.

## upstream native qualification

the official codex installer and a real `0.159.2 → 0.160.0` updater transition
passed in a disposable home on devbox. all three account selectors then launched
`0.160.0`. native linux sandboxing ran the native command and rejected an outside write
under read-only permissions; native app-server initialization and ephemeral thread
creation passed. source bootstrap with minimal path and inherited work selectors
used the fixed personal installation context and added no shell startup block.

plain work-account `codex update` failed installation detection in both releases.
the supported maintenance command explicitly selects the installation context:

```sh
env -u CODEX_MANAGED_BY_NPM -u CODEX_MANAGED_PACKAGE_ROOT CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin" "$HOME/.local/bin/codex" update
```

this limitation is upstream, and the profile wrappers remain simple selectors.
claude's native installer preserved personal channel/disable settings and global
update-policy fields. a work-channel update changed the shared native executable
from `2.1.285` to `2.1.288`; default installer reruns honored the personal stable
channel. different accounts may choose different channels for the same command.

## installed fleet

| boundary | macbook | arch | devbox |
|---|---|---|---|
| native canonical codex publication | `0.159.2` | `0.159.2` | `0.160.0` |
| upstream codex maintenance | actual `0.159.2 → 0.160.0` | actual `0.159.2 → 0.160.0` | `0.160.0` installer rerun |
| shared claude upgrade | actual `2.1.287 → 2.1.288` | actual `2.1.284 → 2.1.288` | upstream auto-update `2.1.287 → 2.1.288`; manual updater then current |
| account/forge/marked launch matrix | 23 native launches before and after | 23 native launches before and after | 23 native launches after maintenance |
| generation/configuration/gateway pid unchanged through upgrades | passed | passed | passed |
| normal host apply | exit `0`; repeat gateway converged | exit `0`; kernel reboot deferred | ai adopted; exit `2` for unrelated operator github enrollment |
| native thread/helper/plugin/provider turns | explicit native thread create/inspect/daemon attach and bounded claude identity turn passed | personal native thread/daemon attachment and fresh claude identity/native turn passed | explicit native thread create/inspect/daemon attach and bounded turn passed; fresh claude identity/native history passed |
| final npm retirement | packages absent; official native repair and 23-launch recheck passed | packages absent; official native repair and 23-launch recheck passed | packages absent; official native repair and 23-launch recheck passed |

private snapshots retain launcher targets, prefix, daemon versions, account
configuration/authentication hashes, accessible history counts and process ids.
no credential contents are included here. existing user sessions and account
daemons are preserved. work-account daemons retain upstream-owned package
selection independently of the cli.

devbox's first gateway apply detected an existing runtime/unit receipt mismatch
and restored the verified prior pair. the retry succeeded with canonical-path
generation `v0.12.2-bb9e0680b9fbf0c122010c7b7b6a3ca7fab6cf807318444fe0d05ea1b96ee7eb`.
no source workaround or receipt bypass was used. attribution of the prior drift
to an external deployment is an inference, not established cause.

installed devbox read-only sandbox qualification passed with `sandbox -P
:read-only`: the bundled executable ran and refused an outside write. an initial
probe used the obsolete `sandbox_mode` key in an unrestricted work account; its
write check failed because that key no longer selects native permissions. the
corrected probe uses the advertised native permission-profile interface.

normal devbox apply from the existing macbook controller adopted the native
providers and returned action `2` for its unrelated github enrollment check.
existing docker containers and reboot-required state were reported deferred.
recorded devbox account authentication/configuration/settings hashes and npm
prefix were unchanged at initial acceptance; all pre-existing provider pids
were then alive. this covers the recorded files, not a byte-for-byte snapshot
of every upstream account file: personal `~/.claude.json` was not included in
the initial hash set.

native codex conversation references were qualified separately from terminal
identity. current skid terminal projection exposes the codex foreground/profile;
it does not promise a codex native reference. helper create/inspect/send/read
and canonical `--remote ... resume THREAD_ID` attachment passed against the
existing daemon, as did the public native read command. upstream forbids
permission overrides for explicit remote attachment; the test used the
canonical command without profile aliases. no wrapper argument parser was added.

root verified absence of all nine former shared codex installation paths,
exact old discovery targets and niels/jarvis client-group grants. the account
socket symlinks now resolve to upstream-owned daemon endpoints. the obsolete
shared-runtime retirement playbook is deleted after that live absence check;
ordinary apply no longer retains cleanup-only ai lifecycle code.

root qualified that exact scrubbed updater command from the actual inherited
npm-marked daemon tool environment. it selected the official native installer,
kept `0.160.0`, and left skid's generation/configuration/pid unchanged. the
explicit context belongs to maintenance documentation; profile wrappers retain
unchanged argument and environment-selection contracts.

macbook and arch native `0.160.0` read-only sandbox probes passed with explicit
`:read-only`: macos refused an owned temporary write with `Operation not
permitted`; arch refused it with `Read-only file system`. neither forbidden file
was created. macbook's account authentication/configuration/settings hashes and
history remained intact. all baseline account daemon/worker pids survived;
seven of eight old npm foreground pids survived. one ended during concurrent
user work; the migration targeted no user session.

arch's ordinary apply completed the required full 89-package upgrade and
reported kernel reboot deferred. the empty root-owned `/etc/ssl/private`
directory had mode `0755` while the signed openssl package specified `0700`;
operator repair restored that exact native-package expectation and verified the
directory remained empty. no source policy or key data was changed.
[ghc runtime registration warnings](issues/arch-ghc-registration.md) remain
recorded separately; actual source shellcheck passed on the installed runtime.

arch's own acceptance terminals were closed before an authoritative `/proc`
scan found zero npm-package consumers. npm removal and immediate official native
`0.160.0` repair passed. all 23 ordinary/forge/marked launches still selected
`0.160.0`/`2.1.288`; gateway pid `997356`, generation and configuration/scoped
command hashes stayed unchanged. ai adoption and gateway reconciliation then
reported up to date. the personal daemon master/worker pids `578448`/`883791`
survived; work/work2 daemons remained absent as in the baseline.

arch history and recorded account hashes were preserved except personal
`.codex/config.toml` and `.claude-work/.credentials.json`, which changed during
native acceptance sessions. current personal codex policy remains
`gpt-5.6-sol`/`xhigh`; authentication succeeds and claude-work remains
`claude.ai`/`max`. codex config contains native tui bookkeeping fields and the
credential change is consistent with upstream refresh, but baseline hashes do
not prove an exact field diff or cause. no credentials or account data were
restored to hide those changes. repository ai code does not write either file.

macbook initially retained seven npm consumers and devbox three. the user closed
those sessions; fresh authoritative process/reference scans found no consumers
or inspection errors before npm uninstall at the recorded prefixes. all three
hosts now have no codex or claude npm provider packages. official default repair
selected codex `0.160.0` and left its latest-channel marker present on every
host. explicit `--release` repair clears that upstream marker; default reruns
restored it on macbook and arch. claude remains `2.1.288`.
final 23-launch checks passed on each host with unchanged
gateway pids, generations, configuration and receipts. devbox authenticated
health, native work2 helper read, claude helper dispatch and native adoption
passed.

nine unselected native versions were removed after reference and selector checks:
three claude versions on devbox, one codex and two claude versions on macbook,
and one codex and two claude versions on arch. independent account daemon
packages and processes remain intact. devbox also removed its obsolete user
ingress-library copy and old provider declaration; all 37 remaining deployed
current libraries/assets match merged source, as do the authoritative privileged
ingress libraries. unrelated historical assets remain outside this cleanup.
devbox's 12 recorded binary/account/configuration/settings hashes, including
personal `~/.claude.json` in the cleanup snapshot, stayed unchanged.

final fresh-source public `./devbox apply` repeated after shared-runtime
retirement-code deletion and returned exactly `2`: no durable changes or ai
actions, only the existing docker/reboot deferrals and operator github enrollment
action. all three hosts finish with shared native codex `0.160.0` and claude
`2.1.288`. source/native probes and test-owned terminals are removed; private
logs and snapshots retain evidence. the completed cutover plan and resolved
native-install/runtime-minimum/npm-retirement issues are deleted; their source
history remains in git.

## 2026-10-13 native launch provenance

source `b9407c431cd9e85401958cf9acff3c5efd34d767` is deployed on macbook,
arch and devbox. all four owned native codex invocation sites remove inherited
installer provenance while preserving account selection, memory selection and
arguments. upstream installation ownership remains unchanged.

| boundary | result and scope |
|---|---|
| compiled integration | each original/final run passed 1,081 controls and checked 100 provenance cases: 78 original leaks, zero final leaks; receivers qualify execution/environment, not native updater or mcp behavior |
| wrapper publication | original full publication failed the narrow claude-preservation predicate; final codex publication passed 62 controls and preservation; full-parent publication passed its separate 34 controls and declared-asset predicate |
| genuine native behavior | seven poisoned personal/work/work2/custom ordinary/scoped doctor routes passed; personal selected standalone, work/custom selected no manager; six actual native mcp add/remove operations preserved staged inputs and unrelated configuration |
| disposable native upgrade | `0.162.0 → 0.162.1` advanced the canonical target; three account commands agreed afterward; three account configuration hashes and four wrapper hashes were unchanged |
| live composition | real http gateway → tmux → bash/zsh → released codex: 12 leaking red cases became 12 clean cases on the same dirty server; the final refactor passed 12 cases on a new dirty server, bound to accepted source hashes |
| installed routing | 15 routes per host, 45 total, passed ordinary/scoped/marked bash+zsh/installed-profile execution; all three selected homes and exact installed codex profile fields were checked; doctor rows, not overall exit status, establish this result |
| client access | the actual three-peer client reached all hosts over authenticated tls; nonpartial `skid list` results included all four profiles |

| host | platform | native codex | provider identities preserved | tmux servers preserved | gateway attachments replaced | strict all-process comparison |
|---|---|---|---|---|---|---|
| macbook | darwin | `0.162.0` | 55 | 1 | 1 | failed |
| arch | linux | `0.160.0` | 4 | 1 | 0 | passed |
| devbox | linux | `0.162.0` | 14 | 1 | 2 | failed |

provider/server identities compare pid, start time and command, without arguments.
gateway activation replaced attachment clients; old gateway ownership is inferred
on macbook and directly observed on devbox. those strict comparison failures
remain failures; the surviving provider/server identities qualify worker
preservation. no production provider upgrade was performed.

all 15 recorded account/helper/wrapper file states matched across each activation
interval, as did canonical binaries, gateway executable/configuration and helper
revision `5aecc2bb3bd08e2c58b79d2e494d2bedb13871c8`. devbox's applying-source files matched
the accepted hashes, owned by `niels`, mode `0644`.

| host | admitted gateway generation |
|---|---|
| macbook | `v0.14.0-c129624c23335235fee779930bef438766c790513fad6c857f84a39291b46854` |
| arch | `v0.14.0-b180e454521f6fcbd2fc6573a3bd86688d01d5cdea62f7e15bbe85cf07986b02` |
| devbox | `v0.14.0-f045d6d750abdbe955440c90ee4f9b9ebee3b0bbc6b4ed1ed9d7fe02e57f921e` |

the first publication transiently replaced `claude-work`; its exact prior bytes
and mode `0755` were restored before gateway activation. this drove extraction
of the existing codex publication owner, whose bounded publication preserves the
installed claude wrapper. no account data was restored.

macbook's `.claude-work/.claude.json` whole hash changed between the initial
snapshot and preactivation. changed fields and cause are unclassified; later
fingerprints cannot establish the earlier difference. the activation interval
matched both whole hashes and the explicit identity/update/mcp projection. this
does not establish byte preservation across the earlier interval.

the checks captured filtered process/hash/routing observations without retaining
raw production doctor reports, account values, tokens or terminal contents.
task snapshots are deleted with the temporary tests; this appendix retains the
dated aggregate evidence.
production model turns and phone transport are `NOT_RUN` and outside this
correction's acceptance. work-account self-update remains the separate
[upstream discovery issue](issues/codex-installation-discovery.md); the supported
maintenance command selected the installation context. the initial five-key
guidance superseded the historical two-key command above;
[checked apply maintenance](gateway-separation-runbook.md#native-ai-maintenance)
now supersedes that direct-update recommendation, as the follow-up below records.
no upstream fork or release
dependency was added.

temporary tests, drivers, receivers, accounts, snapshots, clone and task caches
are deleted. teardown initially missed two orphaned fixture foregrounds and a
stale tmux socket; exact fixture identities were verified, both clients exited
on sigterm, and the stale socket was removed. independent final observation found
zero fixture executable paths and no owned tmux or daemon sockets.

shell syntax, `shellcheck -x`, python syntax and `git diff --check` passed.
no retained test suite is introduced. the
[accepted applying worktrees](codex-native-launch-plan.md#cutover-and-limits)
own future applies; the original dirty checkout remains untouched.

## 2026-10-13 claude maintenance qualification follow-up

five direct native updater cases used copied released binaries in disposable
homes on darwin. each invocation fixed `HOME` and cwd to the fixture owner,
unset `CLAUDE_CONFIG_DIR`, closed stdin, used no tty and passed an allowlisted
environment without real credentials. personal settings bytes were preserved.
these are updater controls, not acceptance of normal-apply claude maintenance.

| case | observed behavior | result |
|---|---|---|
| personal stable | `2.1.288 → 2.1.287`, exit `0`; upstream channel selection can downgrade | `PASS` |
| stable with `minimumVersion=2.1.296` | same starting binary retained `2.1.288`, exit `0`; the selected target was blocked, not replaced by the floor | `PASS` |
| latest no-op | `2.1.296` remained selected, exit `0` | `PASS` |
| network failure | dead, non-listening loopback proxy; exit `1` after 25.4 seconds; canonical link, bytes and version unchanged | `PASS` |
| activation failure | only fixture `.local/bin` made nonwritable (`0555`); exit `0` and successful-update message, but canonical link, bytes and `2.1.288` unchanged; no visible activation error | `RED` |

the activation probe reused the downloaded stable target and restored directory
mode `0755` in `finally`. its failed nonzero-exit assertion remains failed.
an unchanged version proves no observed version change; it does not distinguish
policy/no-op from this silent activation failure or prove the command is newest.
the [upstream activation issue](issues/claude-native-update-activation.md) blocks
strict claude maintenance through the current interface.

scope decision: ship checked codex maintenance and defer claude. current
[runbook guidance](gateway-separation-runbook.md#native-ai-maintenance) replaces
the earlier direct-update recommendation; the five-key command in the historical
acceptance remains historical. this claude qualification does not establish
acceptance or deployment of the new codex maintenance behavior.

| qualified native executable | sha256 |
|---|---|
| starting `2.1.288` | `bbe93063f7a0879a1021b2891e5c9354e5b3b98433e32efe6750f7710afed750` |
| starting `2.1.296` | `c9b5341637becbd423ddffc5b254afb645682a3868cb708bbc6cc0e7bb419937` |
| downloaded stable `2.1.287` | `6eab8333fe2121553100d8f40bfada384a3e989b94f947e18ba6677a6fcb41ea` |

starting binaries admitted the native mach-o header `cffaedfe` and exact native
version output. evidence retains only filtered outcomes, hashes and execution
bindings. no production provider was executed or upgraded; no daemon, tmux or
model turn was started. qualification fixtures and tests are deleted in the
coordinated teardown below.

## 2026-10-13 checked codex maintenance during apply

source `3da3cdb774337129c3cac0c660021cc7edb14bc5` is deployed on all three
applying hosts. normal apply maintains valid native codex through the checked,
unchanged official installer. claude remains bootstrap/adoption only; its
activation-result blocker above remains unresolved.

| boundary | result and scope |
|---|---|
| compiled public `ai_install` | 20 cases, 205 controls and 376 feature checks per phase; controls passed in both; original source failed 211 feature assertions, including 127 mandatory assertions not reached; final source passed all |
| genuine codex owner | four cases, 40 controls and 53 checks passed using real official transport/payload and native version admission; a finite pass-through bash observer captured execution bindings without changing the installer |
| devbox controller | five cases passed through the real controller with a synthetic ansible boundary; unchanged role schema/result-carrier/changed-predicate binding was checked; no actual linux ansible role was executed |

| genuine case | entry point | exit | observed result |
|---|---|---|---|
| upgrade | public `ai_install`, conditional caller | `0` | `0.161.0 → 0.162.1`; `UPDATED`, mutation counter `1` |
| unchanged | public `ai_install`, conditional caller | `0` | `0.162.1` unchanged; exact `UP TO DATE` version-unchanged event, mutation counter `0` |
| refused-proxy download | public `ai_install`, conditional caller | `1` | canonical version unchanged; visible error, no success/mutation event |
| nonwritable command directory | `ai_install_codex` | `1` | visible error, no success/mutation event; current selection and canonical version partially advanced to `0.162.1` |

the permission case uses the provider owner because public `ai_install_dirs`
repairs directory modes; fixture mode was restored to `0755`. synthetic account
policy and separate daemon-package selections matched. twelve compiled process
holds survived their cases and then exited; they qualify loaded-code preservation,
not genuine terminal or daemon services. an initial genuine fixture omitted the
compiled claude receiver's `FIXTURE_RECORD` and produced later `ACTION`, status
`2`; only fixture setup changed before the fresh accepted run. review strengthened
exact no-op event/counter assertions; the final minimal product owner required no
further refactor.

| source or native artifact | retained binding |
|---|---|
| baseline commit | `0df1b89565e2ecb82fe04b18dcf119d593305fed` |
| baseline `lib/ai-tools.sh` sha256 | `6e77315dedef3e7f62a0fc1051f433eabddcf1db041c222e02db423229697da3` |
| accepted owner sha256, unchanged before/after genuine checks | `8412974db24c7924a6fe55df55077ffbddfa87516d03c23bb5c6665cb79710a3` |
| compiled integration driver sha256 | `250a6b45bd7b1de7543155c46fcecf66fc664909cc1e18083f4980a3bbb15342` |
| genuine qualification driver sha256 | `2fc178c1ad0a51d28e05f583aeb2f4ef9e16653fb9fc0dbfad0932a86e4347a2` |
| official installer sha256 | `150e3cf675682efeaac115aa3747add3f27887896d04ce6d0b56478d8b428bf6` |
| starting `0.161.0` native copy sha256 | `12ac11d2c7eee27cfae34393986d7b7c9ed0dea537cb749831cdd7033893e6de` |
| genuine darwin `0.162.1` target sha256 | `74c6a6d263f40d65f99c27a815275f5b4ed0bcc2baecc396b4cf3255498bdfc0` |

rollout published the applying source and invoked the existing codex owner twice
per host. it ran no full host apply, rolling package upgrade or gateway activation.
each host reported `UPDATED`, then version unchanged. seven fresh actual version
routes per host passed: canonical, three ordinary accounts and three scoped
accounts; 21 total.

| host | codex before → after | claude unchanged | recorded processes preserved | strict process comparison |
|---|---|---|---|---|
| macbook | `0.162.0 → 0.162.1` | `2.1.296` | 56/57 | failed |
| arch | `0.160.0 → 0.162.1` | `2.1.288` | 6/6 | passed |
| devbox | `0.162.0 → 0.162.1` | `2.1.288` | 14/14 | passed |

claude executable bytes and selection, and all recorded account/deployment/daemon
selection fingerprints, were unchanged. each deployed owner matched the accepted
sha256.
macbook's missing pid `39978` was a gateway-owned tmux child of `63463`; its exact
role and cause are unknown. gateway `63463`, tmux server `72423` and all native
providers survived. the failed strict comparison remains failed; the
[unclassified child exit](issues/tmux-child-exit.md) limits broader client-preservation claims.

the initial devbox collector included three zombies and encountered failed
`/proc` reads. state filtering was corrected before deployment; accepted live
captures reported no inspection races. the original dirty checkout remained
untouched. this appendix retains filtered aggregate evidence without raw account
values or terminal contents. a finite audit of 26 acceptance receipts found all
432 unique recorded test-process identities absent, with none live or reused;
no fixture executable paths, filesystem sockets or socket links remained.
temporary tests, drivers, native copies, fixture homes, snapshots and remote
code-rollout stages are deleted; their exact local and remote paths are absent.
legitimate applying worktrees remain. shell syntax, `shellcheck -x` and
`git diff --check` passed. no retained test suite is introduced.
