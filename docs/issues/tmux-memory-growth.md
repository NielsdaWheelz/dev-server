# tmux memory growth after long-running agent sessions

problem: tmux can retain far more memory than its reported pane grids and
scrollback. the specific allocation source and recurrence after upgrading remain
unproved.

impact: accumulated memory creates host pressure and can jeopardize active work.
restarting tmux destroys its terminal sessions; codex work must already be owned
by independent account daemons before maintenance.

evidence: on 2026-10-09, macbook's tmux 3.7c server, pid 67531, had a 75.8 gib
physical footprint after roughly 13.5 days. `vmmap -summary 67531` attributed
75.7 gib to swapped/compressed regions. tmux reported about 1.1 mib across its
pane grids and scrollback. jemalloc was loaded; this identifies the allocator,
not the cause. the user confirmed all active codex sessions use daemons before
authorizing the fleet upgrade and tmux restart.

upstream tmux 3.8 includes memory leak fixes, but none has been matched to this
incident. installation and a lower post-restart baseline establish recovery,
not a permanent fix.

recovery on 2026-10-09: the three normal workspace servers were restarted on
3.8 after saving their names, directories and presentation metadata. macbook's
replacement pid 72423 measured 3600 kib physical footprint; arch's pid 801016
measured 6180 kib rss and devbox's pid 3444074 measured 3952 kib rss, both with
zero swap. the 10, 1 and 3 terminals present at the
respective macbook, arch and devbox restarts were recreated as fresh shells.
all observed codex daemon pids and start times were unchanged across each
restart. this proves daemon survival, not uninterrupted progress of every turn.
the separately named devbox notification qa server, pid 987483 on 3.4, was
explicitly excluded and kept its original pid and start time.

resolution: compare the replacement server's memory with its pane history over
representative long-running codex workloads, ideally matching the original
uptime. if disproportionate growth recurs, capture content-free allocation and
client/pane metadata and identify a reproducer before attributing a fix. on macos
use `vmmap -summary <server-pid>`; on linux compare `VmRSS` and `VmSwap` in
`/proc/<server-pid>/status` with tmux's `history_bytes` totals.
