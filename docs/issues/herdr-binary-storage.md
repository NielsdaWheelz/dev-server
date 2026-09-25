# herdr keeps the same release binary in two stores

problem: `herdr_stage_release` prepares `artifacts/<sha>/herdr` and copies
it into `releases/<version>-<sha>/herdr`. that release directory contains
only the binary. validation and retention maintain both trees.

impact: duplicate bytes and bookkeeping without distinct runtime contents.

evidence (2026-09-24): `lib/herdr.sh:573-601` prepares, compares, and copies
the same binary; `herdr_retain` maintains releases and artifacts separately.

follow-up: stage the verified binary directly into its immutable release
directory. retain downloading before the operator stops herdr, pin checks,
atomic promotion, and the current/prior rollback behavior.

resolved when: only one stored copy per retained release is needed and
unchanged apply, pre-staging, activation failure, and rollback still work.
