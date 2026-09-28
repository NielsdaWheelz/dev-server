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

follow-up: if terminations recur, inspect the earlyoom and kernel journals
through the deployment account and identify the concurrent workload. reduce
concurrent heavy jobs or explicitly choose a larger host. do not silently cap
build heaps or remove the host's recovery mechanism.

resolved when: representative concurrent development completes with adequate
memory headroom and no memory-pressure terminations under the selected
workload or host capacity.
