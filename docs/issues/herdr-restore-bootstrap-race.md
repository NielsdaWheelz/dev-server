# herdr restore can report rc 3 from a launchd bootstrap race

problem: `herdr_restore` boots the candidate out and bootstraps the prior job
immediately afterwards. launchd can answer that bootstrap with
`Bootstrap failed: 5: Input/output error` while the previous job is still being
torn down, and `herdr_restore` then returns 3: the prior inputs are back, but
herdr stays stopped, and the operator sees `herdr activation failed; the prior
inputs were restored but herdr remains stopped; rerun apply`.

impact: a failed herdr upgrade on the macbook can leave herdr stopped although
the prior inputs are fine; every herdr terminal on that host is already gone by
then (the operator stopped herdr for the upgrade), so this costs one extra
`apply`, not workers. the pr 4 first install takes the no-prior path and never
restarts, so it does not hit this. linux `systemctl` restarts have not shown it.

evidence (2026-09-23): the disposable darwin qualification's herdr rc 3 proof
reached rc 3 through exactly this path (`rc3.err`: one `Bootstrap failed: 5:
Input/output error`; the herdr log shows one candidate start and shutdown, no
prior start), not through the injected manifest override it meant to exercise.
the truthful text and final state held. `lib/herdr.sh` `herdr_restore` at the
`herdr_start_service … || return 3` line.

resolved when: the restore's restart tolerates launchd's teardown (a bounded
retry of `launchctl bootstrap` after `bootout`, or waiting for the label to
disappear from `launchctl print` first), a disposable-deployment run reaches
rc 3 only through a genuine prior-verify failure, and the recorded text stays.
delete this file with that change.
