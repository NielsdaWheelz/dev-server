# skid recovery can leave `current` and `previous` on the same generation

problem: after a candidate that could not be stopped was left promoted (`current`
on the candidate, `previous` on the prior) and the operator re-applied the
prior pin, `skidbladnir_apply` selected the prior as the rollback target
because the recorded runtime identity matched `previous`, and the promotion
then wrote that same generation to both `current` and `previous`.

impact: none for the running gateway, which is the prior. retention keeps only
that one generation, and a later rollback to `previous` is a no-op, so the
next failed upgrade has no distinct prior to fall back to until one more
successful activation moves the pointers apart.

evidence (2026-09-24): round 4 of the pr 4 proofs on this mac (jarvis
`docs/qualification/2026-09-23-herdr-pr4.md`, row "skid caller, failed upgrade
with a live worker", recovery step): `readlink current` and `readlink previous`
both named the prior generation after the recovery apply.

resolved when: promotion from a rollback target never writes the same
generation to both pointers (leave `previous` on the displaced candidate or
empty), with the disposable recovery flow re-run. delete this file with that
change.
