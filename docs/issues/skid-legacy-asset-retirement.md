# retire superseded skid integration assets after herdr acceptance

problem: the herdr installer no longer manages the tmux-era native control
helper, yet its installed copies must stay until the v0.6.0 gateway rollback
path is no longer needed.

impact: each host keeps unreferenced files that a v0.6.0 rollback (previous
dev-server commit + apply) still requires. removing them early would break that
rollback; leaving them forever is clutter with a stale frozen sdk environment.

evidence (read-only inventory 2026-09-23): `~/.local/bin/provider-runtime-control`
and `~/.local/share/skidbladnir-native-control/` on macbook, devbox and arch;
devbox-only stale `~/.local/bin/skidbladnir-hook` (2026-08-25, no remaining
caller in any pinned release). the v0.6.0 host configs name
`nativeControlPath`; the herdr-era configs do not.

resolved when: coordinated fleet acceptance of the herdr release is recorded and
the operator removes exactly those paths on each host by hand, then records the
removal here and deletes this file. no installer step removes them; no other
path under `~/.local` or any account home is touched.
