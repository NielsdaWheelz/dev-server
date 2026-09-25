# skid activation receipts can describe an unverified pair

problem: successful activation records runtime and unit identities in two
separate atomic writes in `skidbladnir_apply` (`lib/skidbladnir.sh`). interruption between
them can leave the new runtime receipt alongside the old unit receipt.

impact: later recovery can select that runtime and restore that unit as if
the pair had been verified together. whether the combination fails depends
on what changed. this is a failure window inferred from code, not a reproduced
production incident.

evidence (2026-09-24): `skidbladnir_apply` reads the receipts separately and
selects a rollback runtime; `skidbladnir_restore_runtime` restores the recorded
unit and launcher separately.

follow-up: publish the successfully verified runtime/unit pair in one atomic
record. consider one complete activation bundle if it removes the separate
unit-generation bookkeeping; keep independently applied integrations separate.

resolved when: fault injection during an upgrade that changes both runtime
and unit cannot produce an unverified rollback pair. retain recovery from a
candidate that cannot be stopped and the existing no-session-interruption
boundary.
