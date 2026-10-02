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

skid owns `.config/skidbladnir`, `.local/share/skidbladnir`,
`.local/state/skidbladnir`, its unit/launcher, `skid` and `skidbladnir` links,
loopback `7341`, and tailscale https `8443 /v1`. it shares existing provider
accounts and history; maintenance never kills tmux workers. native helper and
explicit claude plugin follow the admitted generation. provider binaries remain
shared host tools.

gateway operations stage declared bytes and modes before consumption. release
pins are exact app-owned artifacts, not name redirects or version intentions.
the binary validates the rendered host configuration. unchanged apply reuses
verified artifacts. authenticated health and the observed executable establish
runtime activation; they do not prove a provider turn or phone attachment.

serve reconciliation changes only `/v1` on `8443`, preserving other handlers
and ports. devbox runs ingress admission/mutation as root and runtime as the
development user. failed ingress can leave a verified runtime applied; report
the partial condition and repair the remaining handler. never reset serve.

## native ai maintenance

all account wrappers, forge profiles, marked shells and native helpers invoke
`$HOME/.local/bin/codex` or `$HOME/.local/bin/claude`. upstream owns their
symlinks, release directories and upgrades. existing processes keep loaded code;
account daemons may use separate upstream-managed packages.

```sh
CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin" "$HOME/.local/bin/codex" update
claude update
```

use that codex command from any account shell. upstream's updater detects the
installation under `CODEX_HOME`; `codex-work update` and `codex-work2 update`
cannot detect the shared personal installation. wrappers remain account
selectors with unchanged argument forwarding. claude's invoking account owns
its update channel; updating it selects one shared binary for both accounts.

for an absent installation or native repair, run the official installer as the
host user. keep `~/bin` ahead of `~/.local/bin` in `PATH` so installer startup
changes cannot supersede account wrappers:

```sh
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin" bash
curl -fsSL https://claude.ai/install.sh | env -u CLAUDE_CONFIG_DIR bash
```

ordinary apply downloads and syntax-checks an installer only for an absent
command. adoption checks native executable and provider version output without
network access. a broken link, script or invalid provider at the canonical path
requires operator repair; apply preserves it and returns `ACTION`.

for an npm cutover, record its prefix, launcher target, versions and current skid
generation. install native codex into a temporary command directory with the
fixed personal installation context, verify it, then publish the canonical
command through the official installer. do not expose the temporary directory
in shell startup files. apply skid once so all consumers use canonical paths;
verify fresh launches and account state. retain the npm package while its
existing processes still need resources. never stop those sessions implicitly.

when old consumers have retired, remove the npm package explicitly at its
recorded prefix. npm removal can unlink the new canonical command too; restore
it immediately with the official installer and verify ordinary and skid
launches. this is a deliberate maintenance window, not recurring apply logic.
before cleanup, recovery restores the recorded launcher and matching skid
generation together. after cleanup, repair native installation first. gateway
rollback does not roll back provider installations or account data.

## provider and jarvis contract

skid's forge profiles and marked shell commands use `.codex`, `.codex-work`,
`.codex-work2`, `.claude` and `.claude-work`. explicit provider commands preserve
account isolation and scrub inherited skid startup context. personal claude
leaves `CLAUDE_CONFIG_DIR` unset. no codex hooks or private account homes are
installed. exact already-owned startup snippets are replaced while unrelated
content, modes and startup symlink identities remain intact.


the managed instant-prompt preamble excludes only the intended shell's pending
skid startup action. skid gateway apply also replaces the recognized existing
preamble in place; a gateway operation need not replace all dotfiles. unfamiliar,
duplicated or changed owned preambles fail preflight. keep the product's
`shell-init` and `assets/skid-provider/shell-init` synchronized.
the early preview is unavailable for new skid startup actions. the theme can
invalidate its shared cache, delaying later ordinary previews until regeneration.

startup edits are not part of gateway runtime rollback. to reverse just this
guard, run from this checkout on the target host before restoring a prior
declaration:

```sh
bash <<'BASH'
source lib/common.sh
source lib/skid-provider.sh
skidbladnir_shell_setup "$HOME" restore-instant-prompt
BASH
```

this restores the original cached preamble, retaining integration, unrelated
bytes, symlinks and modes. repeated reversal is inert. reapplying this
declaration installs the guard again. reversal restores the original launch
conflict too; it is recovery, not the corrected configuration.

on devbox, both gateway and root cli use the same admitted artifact and pin.
`/usr/local/libexec/skidbladnir` is a regular root:root `0755` file. before
switching either executable, compare candidate bytes with the root cli and the
running gateway's `/proc/PID/exe`; an inactive gateway uses its selected
executable. changes require jarvis paused and cleanly stopped: `ActiveState`
`inactive`, `Result` `success`, `MainPID` `0`, exact paused schema v1 true.
identical executable apply requires no service action. the operator keeps
jarvis stopped through the operation; there is no automatic stop or resume.

jarvis deploy owns the private three-peer client at
`/etc/jarvis/agent-client.json`, regular jarvis:jarvis `0600`, and its two path
settings. redistribute that existing fleet configuration explicitly after
bearer rotation. verify under actual service restrictions before resuming.
cognition provisioning is a separate owner task; worker deployment does not
repair or replace it.

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

the deployment hashes each file as `relative-name + NUL + lowercase-sha256 +
newline`, concatenates those records in the order below, then hashes the
concatenation. the result is the generation directory suffix and
`active/<receipt>.runtime.sha256` value. receipts are mode `0600`, generation
directories `0700`. admission requires that mode and equality between the
computed digest and directory suffix. skid has eleven, in this exact order:

1. `skidbladnir` (`0755`)
2. `characters.json` (`0644`)
3. `release.json` (`0644`)
4. `host-config.json` (`0600`)
5. `providers/native-control` (`0755`)
6. `providers/provider-command` (`0755`)
7. `providers/shell-init` (`0644`)
8. `providers/terminal-context-init` (`0644`)
9. `providers/claude-agent-identity/.claude-plugin/plugin.json` (`0644`)
10. `providers/claude-agent-identity/hooks/hooks.json` (`0644`)
11. `providers/claude-agent-identity/bin/agent-hook` (`0755`)

the exact `v0.9.0` skid generation from source
`580e0992d1ee0d7334cefc6561e7f55a5836baf5` has ten files: it omits
`providers/terminal-context-init`. deployment admits that old layout only when
its membership, modes and original ten-file receipt verify. it remains the
rollback target during the `v0.10.0` upgrade; new generations require eleven.

the helper launcher names a separately pinned immutable environment. its shim,
entry point, source commit, lock and installed versions are checked before
activation. the plugin and helper launcher follow the gateway's `current`
pointer, so failed activation restores them together. this costs four more
hashed files and retains private helper environments; it avoids independently
switching dependencies underneath a verified gateway.

the app's `docs/dev-server-handoff.md` and `scripts/fleet` implement this
order, encoding and modes. fleet verification requires the computed digest,
directory suffix and active receipt to agree. native lifecycle acceptance
remains a separate live boundary.

helper environments are never pruned by gateway apply or removal. this
conservatively preserves every retained generation's dependency at the cost of
disk space; automatic helper-environment collection is deferred. any future
cleanup must account for every retained generation and recovery stage before
removing a revision.

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
