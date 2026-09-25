# herdr retry loses the verified prior activation

problem: promotion changes current, config and unit before recording success.
after interruption, `herdr_stage_release` removes stale stages containing the
prior config/unit; `herdr_apply` treats the promoted candidate as its prior
and checks only that an activation receipt exists.

impact: retry can lose the last verified activation and try the failed
candidate again as its own rollback.

evidence (2026-09-25): a disposable home exercised the actual apply, artifact,
staging, snapshot and restore functions with only service/gate calls stubbed.
start with verified a stopped; promote b; send sigkill at the start boundary;
retry b with start failing. retry deleted a's backup, attempted b twice, left
current=b with receipt=a, and reported that the prior inputs had been restored.
no live service was changed; the fixture was removed.

locations: `lib/herdr.sh` functions `herdr_stage_release` (stale-stage sweep),
`herdr_apply` (receipt existence, promotion, final recording), and `herdr_restore`.

follow-up: retain one complete verified activation containing the binary
reference, config and unit until its replacement succeeds. never derive the
verified prior from mutable current. replace fragmented bookkeeping; preserve
the explicit operator stop boundary because stopping herdr ends terminals.

resolved when: interruption after promotion and before success, followed by a
failed retry, restores verified a with its original config/unit and accurate
receipt; candidate-stop failure still preserves its inputs for live repair.
