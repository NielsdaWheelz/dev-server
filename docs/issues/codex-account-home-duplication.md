# codex account homes still have several declarations

problem: `lib/ai-tools.sh` declares normal codex homes for wrappers,
directories and instructions. skid's host template, renderer validation and
scoped provider commands repeat those same homes. these are shared user accounts.

impact: a declaration change can route an account to one home while creating
its directory/instructions elsewhere, or fail skid's configuration admission.

evidence (2026-09-29): `lib/ai-tools.sh` repeats `.codex`, `.codex-work` and
`.codex-work2` across directory, wrapper and instruction installation.
`assets/skidbladnir/host-config.json`, `lib/skidbladnir.sh` and
`assets/skid-provider/provider-command` also encode those paths. retirement
does not resolve this remaining consistency issue.

follow-up: declare the normal account paths once for the host and use those
paths consistently, preserving command behavior and existing account state.
do not migrate providers or introduce an account registry to resolve duplication.

resolved when: one declared normal-home change produces consistent consumer
paths without moving or replacing existing credentials/configuration/history,
and explicit account selection remains unchanged.
