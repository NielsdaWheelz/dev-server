# native ai installation plan

implement the accepted [ai installation contract](../SPEC.md#files-and-ai-tools)
on macbook, arch and devbox. every account and skid consumer will use one
canonical native cli per provider per host user. upstream installers will own
upgrades; ordinary apply will bootstrap missing tools and adopt existing ones.
implementation and host cutover are pending.

## current state and target

the 2026-10-02 devbox investigation found one npm codex cli at 0.160.0 shared by
personal, work and work2, and one native claude installation at 2.1.287 shared
by both claude profiles. skid invokes the native executable inside codex's npm
package. host apply resolves provider releases through npm and upgrades them.

the target keeps the existing account homes, overrides, permission arguments,
instructions, status line and claude identity plugin. all consumers invoke
`$HOME/.local/bin/codex` or `$HOME/.local/bin/claude`. upstream owns their symlinks
and package layouts. dev-server neither pins versions nor implements an updater.
working installations require no provider release lookup during apply; other
host package operations still require the network.

the three codex daemons currently use separate account packages and updaters,
all observed at 0.160.0. those remain upstream-owned. a shared cli does not
require identical running daemon versions or a single daemon package directory.
this settles the daemon-sharing ambiguity; it does not change those runtimes.

## qualify native maintenance

before source implementation, use a disposable home to qualify the official
codex installer and updater with personal, work and work2 account selectors.
establish that the shared native command executes directly and includes the
resources needed for sandboxing and daemon control. installer fixtures alone
cannot establish this.

the important open question is how `codex update` locates its installation when
the invoking account has a different `CODEX_HOME`. qualify the normal shell
command, the canonical executable and updater dispatch in that situation.
installer reruns have a defined fallback: explicitly set the installation home
to `$HOME/.codex` and the command directory to `$HOME/.local/bin`.

require normal host maintenance to update the shared cli and leave account
selection intact. if upstream cannot provide plain `codex update` in an account
context, record the exact limitation and settle the documented upgrade command
before shipping. do not silently add per-account cli installations or a wrapper
that parses arbitrary cli arguments. verify claude's native repair and channel
behavior with existing settings as well.

## change the responsible modules

| module | change |
|---|---|
| `lib/ai-tools.sh` | bootstrap absent native commands; adopt working native providers; report legacy or broken commands as actions; remove npm manifests, release lookups, version comparisons and the ai runtime gate |
| `lib/skid-provider.sh` | return and validate canonical native commands; stop requiring npm directories or a particular claude version-directory layout |
| `lib/skidbladnir.sh` | render canonical paths into forge configuration and scoped commands; retain account environments and native process identity |
| `assets/dotfiles/zshenv` | retain wrapper precedence; update the comment that describes a raw npm binary |
| `workstation`, ansible ai role | retain the shared ai entry point and host-user execution; remove only prerequisites that have no remaining consumer |
| readme and maintenance runbook | replace current installation guidance after implementation and qualification |

keep codex and claude bootstrap code explicit. reuse the existing temporary-file
download and syntax-check pattern where it simplifies the code. verify the
callable native provider at the canonical path without binding consumers to
installer internals. do not add an installation registry, compatibility shim,
custom provider service or generic package-manager framework. keep existing
node/npm packages and the user's npm prefix; they may serve other tools.

ordinary apply must distinguish an absent command from a broken symlink or
legacy npm launcher. it must not overwrite a conflict or migrate it implicitly.
an install failure remains a failure with its observed partial state and repair
action. adoption never runs an installer merely to find out whether an update
exists. bootstrap must not rewrite existing user update policy in account
settings; qualify any native-installer settings changes before acceptance.

## verify the source change

use a small temporary integration probe for the installation state table:
absent commands bootstrap; working native commands are adopted; legacy npm and
broken commands produce actions; installer failure cannot report success.
adoption must work with provider download and release endpoints unavailable.
that checks this subsystem, not offline whole-host apply.

render skid configuration and execute every ordinary and marked profile against
native stand-ins. verify canonical command paths, account selection, unchanged
arguments and plugin dispatch. change the stand-in executable behind its
canonical symlink without rendering again; every subsequent launch must select
the replacement. retain the bare codex override and unset personal claude home.

run bash/zsh syntax, shellcheck and relevant ansible syntax checks for changed
files. remove temporary probes and record their scope. native sandboxing,
foreground identity, daemon attachment and real update behavior still require
native qualification and live acceptance.

## migrate one host at a time

deploy the qualified implementation to one host, verify it, then proceed to the
next. use the existing deployment identity and gateway commands. no ordinary
apply performs this migration automatically.

1. record the canonical commands, installed cli versions, npm prefix, skid
   generation and running daemon versions. record enough account-state evidence
   to check authentication, settings and history without exposing credentials.
2. stage codex through the official installer using a temporary command
   directory and fixed personal installation home. arrange the installer's path
   and check startup files so no temporary command directory remains in future
   shells. verify the native package before switching the canonical launcher.
   use the currently installed release for the initial cutover when upstream
   publishes it; this is an operator choice for that cutover, not a repository
   pin.
3. publish the canonical codex launcher through the official installer with the
   fixed installation context. retain the old npm package for recovery and for
   any still-running consumers. adopt claude's existing native installation.
   avoid npm operations between staging and launcher publication.
4. apply skid once to replace its npm paths with canonical paths. verify new
   forge and marked-terminal launches and native helper dispatch. existing
   provider sessions and account daemons must not be stopped by the cutover.
5. run ordinary host apply and repeat the relevant ai/gateway reconciliation.
   confirm that ai adoption selects no release and invokes no updater; verify
   account state and daemon ownership remain intact.
6. when old package consumers are retired, explicitly remove the obsolete npm
   codex installation at its recorded prefix. npm removal may remove the new
   canonical launcher too: immediately restore it with the official native
   installer using the selected release policy and verify every consumer.
   schedule this small repair window when no new launches or package-dependent
   work will be affected. it is operator cleanup, not recurring apply behavior.

the cutover changes provider paths and skid configuration together. do not
leave a deployed gateway referencing an npm executable that cleanup has removed.
skid gateway rollback restores its own generation; it does not restore a
provider installation. keep rollback inputs until the replacement is verified.

## accept native upgrades

on each supported host, use a normal upstream upgrade or installer rerun and
verify every account launches the selected cli version. do not edit dev-server,
apply host configuration, rerender skid or restart the gateway between the
upgrade and those launches. a published newer release is needed to prove an
actual version transition; an up-to-date response proves only updater dispatch.

verify skid sees the native foreground process, can create and inspect a codex
thread, and can attach through the selected account's existing daemon. verify
claude-work identity plugin dispatch and a bounded provider turn. confirm
native sandboxing on linux and the native executable/resource layout on macos.
check existing authentication and accessible history, and that the canonical
command remains shared after an update invoked from a work account.

inspect each daemon with upstream `app-server daemon version` separately.
do not infer daemon convergence from cli version output. leave daemon updates
to the operator and upstream; `update --from-cli` copies and pins a selected
daemon package and is not a default synchronization policy.

## recover a failed cutover

before npm cleanup, restore the recorded npm launcher and prior skid generation
as a pair if native qualification fails. the retained npm package supplies the
old executable. do not roll back account data or stop daemons as part of this.
restore the pre-migration ai tooling source if ordinary apply must resume with
npm; the new contract deliberately reports that installation as a migration
action.

after npm cleanup, repair the native installation through its official installer
first. if returning to npm is necessary, reinstall the recorded prior package
at its prior prefix, restore its canonical launcher and restore the matching
skid generation. retain the original launcher target and gateway generation
until recovery is verified. temporary shell changes must also be reversed.
no recurring rollback service or second installation manager is introduced.

## close the remaining records

keep [the native-install issue](issues/codex-native-installation.md) open until
source and installed-host acceptance pass. close
[the runtime-minimum issue](issues/ai-runtime-minimum-policy.md) when the old
ai-specific gate is removed and remaining runtime requirements have owners.
unrelated account-home declaration cleanup remains outside this migration.
record qualification limitations honestly. after implementation and fleet
acceptance, remove completed issue records and this cutover plan; retain the
durable contract and upgrade guidance in the spec, readme and runbook.

## upstream references

- [codex native installation and installer reruns](https://learn.chatgpt.com/docs/codex/cli)
- [codex installation context](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [codex update command](https://learn.chatgpt.com/docs/developer-commands#codex-update)
- [claude native installation and updates](https://code.claude.com/docs/en/setup)
