# native ai installation validation

2026-10-02. source branch `feat/native-ai-installation`, based on `0ed84b1`.
source, disposable qualification and installed-fleet native acceptance passed.
conditional npm retirement remains on macbook/devbox while old sessions run.
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
| npm retirement | seven active consumers retained | package removed; official native repair and 23-launch recheck passed | three active consumers retained |

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
prefix are unchanged; all pre-existing provider pids remain alive. this covers
the recorded files, not a byte-for-byte snapshot of every upstream account
file: personal `~/.claude.json` was not included in the initial hash set.

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

conditional npm retirement on macbook/devbox is the explicit preservation state
required while their old consumers run. every new consumer uses canonical native
commands. the [retirement record](issues/npm-codex-retirement.md) owns the final
operator cleanup; no compatibility installer or automatic process stop remains.

final fresh-source public `./devbox apply` repeated after shared-runtime
retirement-code deletion and returned exactly `2`: no durable changes or ai
actions, only the existing docker/reboot deferrals and operator github enrollment
action. all three hosts finish with shared native codex `0.160.0` and claude
`2.1.288`. source/native probes and test-owned terminals are removed; private
logs and snapshots retain evidence. the completed cutover plan and resolved
native-install/runtime-minimum issues are deleted; their source history remains
in git.
