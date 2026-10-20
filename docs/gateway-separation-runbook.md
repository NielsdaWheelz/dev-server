# skid gateway maintenance and retirement

source work is separate from live acceptance. ordinary host apply manages shared
host tools; it installs no herdr runtime, hook, gate or gateway. gateway apply
installs only skid. retired-product installation and removal commands are gone.

## current commands and ownership

```sh
./workstation gateway apply skidbladnir
./devbox gateway apply skidbladnir
./workstation gateway remove skidbladnir
./devbox gateway remove skidbladnir
```

these commands delegate to the reviewed standalone bootstrap with its pinned
release version, and to `skid uninstall`. only devbox receives the authoritative personal yaml and
`skid apply`; membership and generated state stay owned by skid. host provider
tools/accounts/daemon preparation remain independent.

the pending release pin reports action before installation. after review,
replace it with version, source commit and bootstrap sha256. do not deploy the
old-wire v0.18 archive or restore a symlink across incompatible private state.
the root-owned staged conversion/enrollment preserves handles, observer/device
memory and existing work before matching host/phone activation.

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
does not restart providers or update separately owned account daemons.

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

gateway rollback does not roll back provider installations or account data.

## provider and jarvis contract

personal yaml uses ordinary wrappers for `.codex`, `.codex-work`, `.codex-work2`
and `.claude-work`. it explicitly carries codex `--yolo`/`--remote` and claude's
permission and identity-plugin arguments. ordinary account wrappers own account
selection and memory credentials. the personal plugin is installed by AI apply
under `~/.local/share/dev-server/claude-agent-identity` and invokes
`skid agent-hook Claude SessionStart`. no deleted provider-command shim, injected
alias or copied shell-init remains.

ordinary AI apply invokes `app-server daemon start` through each codex account
wrapper. upstream owns start/reuse; failed preparation reports action and never
forces a restart/upgrade. skid consumes existing daemons only. provider data,
settings, history and running work remain intact.

jarvis consumes the matching cli and `JARVIS_AGENT_STATE_DIRECTORY`, with no
model/effort creation overrides or copied client-json reader. installed worker
cutover is BLOCKED pending its separate service-state-access issue: the `jarvis`
uid with `ProtectHome`/`NoNewPrivileges` cannot read `niels`'s private live state.
do not copy stale snapshots or add a privilege bridge here. old code must settle
unfinished actions before the v8 schema/cli cutover. cognition is separately owned.

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
uses only its reviewed source commit/checksum and pinned release version.

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
