# codex account homes still have several declarations

problem: `lib/ai-tools.sh` declares normal codex homes for wrappers,
directories and instructions, while herdr integrations, the gate and gateway
profiles also declare those same homes. these are shared user accounts.

impact: a declaration change can route an account to one home while creating
its directory/instructions elsewhere, and the gate rejects the new home.

evidence (2026-09-25): before shared-runtime retirement, an in-memory
`profiles.json` work-home change to `.codex-employer`
changed the generated launcher while installer fixtures selected `.codex-work`.
the current consumers are `lib/ai-tools.sh`, `lib/herdr.sh`,
`assets/herdr/herdr-gate`, both gateway host configs/renderers and skid's
scoped provider launcher.

status (2026-09-28): retirement removes `profiles.json` and renders wrappers
directly in the ai installer. the remaining consumers still repeat the same
normal homes; retirement does not resolve this consistency issue.

follow-up: declare the normal account paths once for the host and use those
paths consistently, preserving command behavior, account state and the gate's
explicit command policy. original skid now uses the same accounts.
do not migrate providers or introduce an account registry to resolve duplication.

resolved when: one declared normal-home change produces consistent consumer
paths without moving or replacing existing credentials/configuration/history,
and unrelated gate commands remain refused.
