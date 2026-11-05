# skid gateway maintenance and retirement

source work is separate from live acceptance. host apply maintains skid and
shared tools; retired herdr installation and removal commands remain absent.

## current commands and ownership

```sh
./workstation apply
./devbox apply
```

apply verifies the reviewed bootstrap source/checksum, then skid selects and
verifies the latest signed stable release. only devbox receives the authoritative
yaml and `skid apply`; membership and generated state remain skid-owned. standalone
`skid uninstall` is the separate removal operation and retains its drain rule.

signed skid v0.24.2 is public and the owner-authorized devbox terminal cutover
is complete. ordinary devbox apply returned `2` for a missing memory bundle and
busy docker activation. mac deployment remains held; arch has not been deployed.
for a refused runtime replacement,
finish work and pause session creation; perform separately authorized maintenance
from outside tmux using the reviewed release installer. it stops and reconstructs
the workspace. see [qualification](issues/unified-apply-qualification.md).

the earlier `v0.20.x` fleet migration was a lockstep cutover of three hosts and the
phone. do not deploy old-wire v0.18 or restore incompatible private state.
that migration introduced a fresh fleet, hub attention and schema-2 workspace
recovery, with no converters. skid's [release cutover](https://github.com/NielsdaWheelz/skidbladnir/blob/main/docs/issues/release-cutover.md),
[attention cutover](https://github.com/NielsdaWheelz/skidbladnir/blob/main/docs/issues/attention-cutover.md)
and [workspace recovery](https://github.com/NielsdaWheelz/skidbladnir/blob/main/docs/session-recovery.md#cutover-and-qualification)
own the steps.

a skid release that changes the yaml schema needs one manual step on devbox.
`lib/skidbladnir.sh` installs the desired yaml after the release installer, so
the new serve first starts on the live `~/.config/skidbladnir/config.yaml`. no
order works both ways: the old serve rejects new keys and the new serve rejects
removed ones. before installing such a release, stop serve and edit the live
file to parse under the new schema; dev-server's apply then replaces it with the
desired yaml.

## native ai maintenance

all personal account wrappers invoke
`$HOME/.local/bin/codex` or `$HOME/.local/bin/claude`. upstream owns their
symlinks, release directories and upgrades. existing processes keep loaded code;
account daemons may use separate upstream-managed packages.

normal apply on macbook, arch and devbox is the checked codex maintenance path. it
downloads the unchanged official installer, checks nonempty content and shell
syntax, checks execution status, then revalidates the canonical native command.
it runs even for healthy codex, using the fixed host-owner `HOME`, personal
`CODEX_HOME`, `.local/bin` installation directory, owner cwd and closed stdin.
this is the upstream installer with explicit context, not a custom installer.

installer execution clears `CODEX_MANAGED_BY_NPM`, `CODEX_MANAGED_BY_BUN`,
`CODEX_MANAGED_BY_PNPM`, `CODEX_MANAGED_BY_VITE_PLUS` and
`CODEX_MANAGED_PACKAGE_ROOT`, including empty and `0` values. it fixes
`CODEX_INSTALL_DAEMON_ONLY=0`, unsets `CODEX_INSTALL_DEFER_SELECTION`,
`CODEX_INSTALL_IF_LATEST` and `CODEX_INSTALL_IF_CURRENT`, and preserves upstream
release/transport selectors such as `CODEX_RELEASE`. upstream defaults to latest
and owns layout and integrity. inherited work context cannot redirect maintenance.

healthy codex maintenance needs network access and may change the version.
`UPDATED` records any version difference, including a downgrade; unchanged means
no observed version change, not proof of newest. failure returns `ERROR`, status
`1`; earlier completed operations and partial upstream state may remain. repair
and rerun; there is no fallback or automatic rollback. normal apply also runs the
host's ordinary package policy; deploying this source change does not require a
full rolling host upgrade or add a public maintenance mode.

working native claude is adopted without installer, updater or release lookup.
missing claude still uses its official installer. its
[activation-result defect](issues/claude-native-update-activation.md) blocks
strict updater integration. normal apply preserves account update policy and
uses each codex wrapper to start/reuse, update and inspect its native daemon.
upstream activation may interrupt active work.

generated account wrappers, version inspection and the
memory configuration writer clear the same five provenance keys before native
invocation.
wrappers retain account and memory selection; ordinary arguments remain literal,
and configured profile commands explicitly retain the intended provider flags.
parent shells and existing clients keep their environments. upstream cli upgrades
need no gateway reapply; hub yaml owns changed profile commands.

direct `codex update` and the upstream curl-to-shell one-liner can hide download
failure through their shell pipeline; see the [pipeline issue](issues/codex-self-update-pipeline.md).
work/work2 updates also cannot detect the shared personal installation; the
[discovery issue](issues/codex-installation-discovery.md) remains upstream.
wrappers do not parse maintenance arguments.

manual claude maintenance remains upstream-owned. if using its updater, select
the personal home and cwd explicitly. it can report success while the canonical
selection remains old; this command has no strict activation-failure guarantee:

```sh
(cd "$HOME" && env -u CLAUDE_CONFIG_DIR HOME="$HOME" \
    "$HOME/.local/bin/claude" update </dev/null)
```

for native repair, use the official [codex installer](https://chatgpt.com/codex/install.sh)
or [claude installer](https://claude.ai/install.sh) as the host owner with the
installation context above. keep `~/bin` before `~/.local/bin` in `PATH`.
a broken link, script or invalid provider at the canonical path requires
operator repair; apply preserves it and returns `ACTION`, status `2`.

skid service recovery does not roll back provider installations or account data.

## provider and jarvis contract

personal yaml command values are exactly `codex`, `codex-work`, `codex-work2`,
`claude-work`. retain profile labels/order, provider/home observation metadata,
hub/machine overrides and private options. ordinary initialized shell aliases
and account wrappers own permissions, account/home selection and memory.
no flags/socket/plugin arguments are added. bare codex follows inherited
`CODEX_HOME`; named work wrappers force their established account home.

the following are the earlier plugin-retirement instructions, not current apply
behavior. source publication/staging of the claude identity plugin was removed;
installed cleanup was a separate coordinated cut. the verified plugin has only a
`SessionStart` identity hook whose failure does not block claude, with no other
events or blocking-on-failure policy (see the [official hook failure contract](https://code.claude.com/docs/en/hooks#other-exit-codes)).
that exact plugin may be removed while the existing claude process keeps running;
a cached hook may briefly warn if its removed command is invoked. do not stop the
process automatically.

remove only the three deployment-owned files `bin/agent-hook`,
`hooks/hooks.json` and `.claude-plugin/plugin.json`, after matching each file's
hash to its reviewed source and confirming no extra content, under both
`~/.local/share/dev-server/claude-agent-identity` and
`~/.local/share/dev-server/assets/claude/agent-identity`; remove only empty
directories afterward. unexpected bytes, hook policy or content block cleanup.
retain immutable skid installation generations. no recursive sweep, permanent
cleanup machinery or compatibility shim. old inert tmux options need no migration.

the earlier coordinated cutover changed only the four command values in the
private desired yaml and staged matching host/android artifacts. jarvis source
was merged with its runtime stopped; source changes alone do not establish
installed parity.

ordinary apply invokes native start/reuse, update and version through each codex
account wrapper. it does not force a restart. update may interrupt clients; daemon
readiness does not prove that conversations continued. skid consumes existing
daemons only; provider data, settings and history remain upstream-owned.

jarvis consumes the matching cli and `JARVIS_AGENT_STATE_DIRECTORY`, with no
model/effort creation overrides or copied client-json reader. installed worker
cutover is BLOCKED pending its separate service-state-access issue: the `jarvis`
uid with `ProtectHome`/`NoNewPrivileges` cannot read `niels`'s private live state.
jarvis remains STOPPED while the separately authorized skid deployment proceeds.
do not copy stale snapshots or add a privilege bridge here. old code must settle
unfinished actions before the v9 terminal-only schema/cli cutover. cognition is separately owned.

## retirement boundary

the root operator completed herdr and herdr-mobile retirement on macbook, devbox
and arch. owned supervisor restart paths were disabled before stopping native
servers; provider integrations and exact ssh gate entries were removed. owned
configuration, share/state trees, units, commands, gates, receipts, mobile gateway
credentials and tailscale https `8444 /v1` were purged and validated absent.
the devbox's three `/etc/jarvis-herdr` files were removed by root. cleanup-only
source and command selectors are deleted; no runtime, hook or ssh gate installer
remains here. ordinary apply never performs destructive retirement or discards workers.

preserve skid workers, native provider history/authentication, unrelated hooks,
settings, ssh access, serve handlers and permanent mobile signing backups. skid
phone installation remains in place with its data and pairings preserved. the root
cutover record owns live absence and preservation evidence. normal host apply
and gateway apply completed on all three hosts with skid `v0.10.6` and stock
codex `0.159.2`; installed native lifecycle, fleet tls, the actual jarvis uid's
production client and owner phone attachment passed everywhere. jarvis remains
disabled, inactive and paused; pre-existing shared codex app-server process
lifetimes were preserved. activation and cognition remain separately owned.

## generation receipt contract

the old eleven-file generation/rollback receipt and helper checkout are retired.
skid's signed standalone archive and installer own release identity, immutable
assets, locked helper dependencies, services, startup blocks and removal.
dev-server reads none of those private receipt schemas. local bootstrap admission
uses its reviewed bootstrap source commit/checksum; skid selects the signed release.

## verification and limits

source checks cover bash/zsh syntax, shellcheck, declarative parsing and ansible
syntax. disposable probes exercise actual installer/file code and command
selection with owned fixture data. native-service stand-ins establish control
flow only; they do not qualify systemd, launchd, provider turns, real-service
jarvis containment or phone use. every unperformed boundary is `not_run`.

[installed-fleet qualification](gateway-separation-validation.md#2026-09-29-installed-fleet)
records completed retirement, ordinary apply and native/device acceptance.
arch's initial package-signature mirror timeout installed no packages; the native
installer retry passed without a signature bypass. devbox and arch reported
`system.reboot` deferred; neither was rebooted. those pending activations are
outside retirement. historical coexistence evidence qualifies only its recorded
revisions.
