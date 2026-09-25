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
record. make one complete activation bundle own the binary reference, host
config and service definition. this should replace separate unit generations,
receipts and backups rather than add another recovery branch. keep independently
applied integrations separate.

audit (2026-09-25): `skidbladnir_apply` maintains an extracted artifact cache,
runtime generations, unit/launcher generations, current/previous pointers,
two receipts and stage backups. the separately recorded pair and the
`skid-current-equals-previous-after-recovery.md` issue share this fragmented
state model. the 11-line launcher is another retained activation input; direct
service execution could remove it, after qualifying launchd's behavior when
the executable is unavailable. do not merge herdr's terminal lifetime with
the gateway's independently restartable lifetime.

resolved when: fault injection during an upgrade that changes both runtime
and unit cannot produce an unverified rollback pair. retain recovery from a
candidate that cannot be stopped and the existing no-session-interruption
boundary.
