# concurrent development workloads can exhaust host memory

problem: concurrent development jobs have exhausted the devbox's 7.6 gib of
usable ram and 4 gib swap. the incorrect earlyoom victim preference has been
repaired, but workload demand can still exceed host capacity.

impact: earlyoom may terminate builds or editors under memory pressure; its
preference for preserving agents is not immunity. kernel oom counters do not
record earlyoom's userspace signals.

evidence (2026-09-28, before repair): `/etc/default/earlyoom` and pid 901 contained
`--prefer '^(chrome|node|codex|claude|cursor-server|python|java|ruby)$'`.
the 7.6 gib host has 3.5/4 gib swap occupied; an active effect diagnostics job
used 3.1 gib rss with a 4 gib node heap allowance. two remote jetbrains servers
held about 2.1 gib of swapped memory. kernel and readable cgroup oom-kill
counters are zero. the user supplied privileged earlyoom logs confirming
codex terminations at 16:57:58, 16:58:02, 17:24:18 and 17:24:26, and a claude
termination at 17:23:17. these were memory-pressure terminations, not merely
application errors. the small resident sizes of these victims do not capture
swapped pages or virtual memory considered by earlyoom's scoring.

repair applied (2026-09-28): the targeted play completed with 21 successful
tasks and no failures, including earlyoom policy activation and all three
codex daemon/sandbox checks. `ansible/roles/base/tasks/ai-runtime.yml` retains
earlyoom, removes the preferred-victim list, and adds codex/claude to its
avoidance list. the installed configuration matches and earlyoom is enabled.
the old shared codex units and discovery links are gone; jarvis is disabled.

recurrence (2026-10-02): at 00:35:35 utc, earlyoom terminated `tmux: server`
(pid 385785, score 909, rss 119 mib). available memory was 762/7751 mib and
free swap was 1/4095 mib. skid went from four sessions to zero by 00:35:37.
the avoidance regex matched only the bare name `tmux`, missing the server's
actual process name. the policy now matches both `tmux` and `tmux: server`.
inspect the incident with
`sudo journalctl -u earlyoom --since '2026-10-02 00:35:30' --until '2026-10-02 00:35:40' --no-pager`.
at 00:38:17 a surviving effect diagnostics job used 3.05 gib rss and an
overlapping typescript check used 0.83 gib. this establishes substantial check
memory use, but no per-process snapshot exists at the instant of the kill.

repair verified (2026-10-02): the three policy tasks installed the correction
and restarted earlyoom; a second run changed nothing. the installed file and
running daemon arguments match the repository. the old expression fails the
server-name regression; the correction passes nine positive/negative name
checks and matches the restarted server's actual `/proc` name. the full apply
playbook passes its syntax check. skid was restarted and lists six reachable
terminals: five shells restored from the 00:22 layout and a recovery shell.
the layout restore does not resume the agent conversations.

follow-up: if terminations recur, inspect the earlyoom and kernel journals
through the deployment account and identify the concurrent workload. reduce
concurrent heavy jobs or explicitly choose a larger host. do not silently cap
build heaps or remove the host's recovery mechanism.

resolved when: representative concurrent development completes with adequate
memory headroom and no memory-pressure terminations under the selected
workload or host capacity.

native-control tradeoff (2026-09-29): a skid-created codex thread uses the
upstream native daemon selected by its existing `CODEX_HOME`. that owner persists after the last tui exits until
an explicit `codex app-server daemon stop` under the selected account. the
provider's lifecycle implementation has no idle timeout or reference-counted
shutdown. this removes unconditional startup of three shared services, but
using all three accounts can retain three owners and their loaded threads.
skid adds no daemon supervisor or automatic stop; stopping can interrupt work.

acceptance still requires observing retained memory and headroom with the
intended simultaneous account workload. measure that boundary during approved
live qualification; it is NOT_RUN here. automatic idle eviction would require
a separately accepted first-party lifecycle change.
