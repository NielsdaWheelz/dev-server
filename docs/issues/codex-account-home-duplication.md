# codex account homes still have several declarations

problem: `assets/codex/profiles.json` drives ordinary codex account wrappers,
while directories, instructions, herdr integrations, the gate and mobile
profiles also declare those same normal homes. these are shared user accounts,
not cognition-only state.

impact: a declaration change can route an account to one home while creating
its directory/instructions elsewhere, and the gate rejects the new home.

evidence (2026-09-25): an in-memory work-home change to `.codex-employer`
changed the generated launcher while installer fixtures selected `.codex-work`.
the current consumers are `lib/ai-tools.sh`, `lib/herdr.sh`,
`assets/herdr/herdr-gate`, `assets/herdr-mobile/host-config.json` and its renderer.

follow-up: resolve the existing declaration once for the host and use those
paths consistently, preserving command behavior, account state and the gate's
explicit command policy. original skid's scoped private homes remain separate.
do not migrate providers or introduce an account registry to resolve duplication.

resolved when: one declared normal-home change produces consistent consumer
paths without moving or replacing existing credentials/configuration/history,
and unrelated gate commands remain refused.
