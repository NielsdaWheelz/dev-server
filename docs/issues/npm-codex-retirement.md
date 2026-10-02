# retire npm codex resources after their sessions finish

problem: source and new-launch paths have cut over to canonical native codex,
but pre-existing npm-based cli processes still need their package resources.
removing the package while those sessions run would violate the cutover's
preservation requirement.

impact: macbook and devbox temporarily retain obsolete npm package storage.
ordinary apply no longer installs, checks or updates it; every new ordinary,
forge, marked-shell and helper consumer selects the canonical native command.
this is conditional operator retirement, not a second managed installation.

evidence (2026-10-02): baseline macbook had eight npm-native user consumers and
devbox had three. npm prefixes were `/Users/nnandal/.local` and
`/home/niels/.local`. the migration stopped no user sessions or account daemons during native
publication and upgrades. seven of eight baseline macbook npm foreground pids
survived; one ended during concurrent user work. arch had no old foreground consumers and its package removal, immediate native
repair and 23-launch recheck passed. seven macbook consumers and all three
devbox consumers still required their old package at final acceptance.

resolution: let the existing sessions finish or close them deliberately. verify
no live processes use the recorded npm package or its bundled resources. during
a short launch-free maintenance window, explicitly uninstall `@openai/codex`
at the recorded prefix. npm removal can unlink the native canonical command;
immediately restore it through the official installer with
`CODEX_HOME="$HOME/.codex" CODEX_INSTALL_DIR="$HOME/.local/bin"`. retain account
state and leave daemon packages to upstream.

resolved when: no live npm package consumers remain, the npm package is absent,
and canonical codex plus every ordinary/skid profile launches the shared native
version. confirm gateway configuration still stores canonical paths. the
[native maintenance runbook](../gateway-separation-runbook.md#native-ai-maintenance)
owns repair and recovery steps. active user sessions are the present blocker;
there is no automatic process termination or cleanup service.
