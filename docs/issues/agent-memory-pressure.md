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

second recurrence (2026-10-02, 16:35–16:38 utc): the corrected tmux regex was
active. earlyoom killed buildkit workers and rootless docker, two `MainThread`
processes at 2566/2647 mib rss, then skid (11 mib), shells (3–6 mib), dbus and
gpg-agent. swap was exhausted. systemd still reported tmux running after skid
exited; no earlyoom kill of tmux or kernel oom kill appears in this interval.
tmux was absent afterward; its precise exit cause is not logged.

the user manager had `OOMScoreAdjust=100`, and systemd's user-service default
added another 100. tiny service-tree processes consequently scored about 800
before avoidance, ahead of many much larger login-shell workloads with zero
adjustment. skid handled the termination with exit status zero, so
`Restart=on-failure` left the gateway inactive.

second repair: the development account's user manager now has adjustment -100,
giving its services a zero default. apply updates the running manager,
reexecutes it only when its default differs, and clears the old inherited +200
inside its service tree without restarting workloads. other adjustments and
login sessions are left unchanged. skid's linux unit now uses `Restart=always`.
the active daemon, tmux, rootlesskit and sampled shells retained their process
identities while moving from +200 to zero; a fresh transient service reported
zero. repeat apply changed nothing. a transient service with the new restart
policy restarted after handling termination with exit zero, and stayed stopped
after an explicit stop. skid was recovered with the saved 16:31 layout; layout
restoration alone does not resume conversations.

third recurrence (2026-10-05): earlyoom pid 3835046 sent sigterm to the
production `tmux: server` pid 3187241 at 15:31:57.960278 utc (08:31:58 pdt),
reporting 5384 mib rss. available memory was below 10% and free swap was zero.
the gateway listed three sessions at 15:31:54.136601 and zero at
15:32:03.996616. read-only inspection subsequently found no tmux process and
connection refusal on the production socket. the gateway stayed running;
production ingress still targeted port 7341 and authenticated requests passed.
the notification qa services had already been removed.

the installed configuration and actual daemon argv both contain the corrected
`tmux(: server)?` avoidance expression as one argument. this is exhaustion
despite avoidance, not another name/quoting mismatch. the user reports nexus ci
was running; its contribution at the kill is unmeasured. tmux's own 5384 mib
allocation is established, but its cause is not. installed tmux is
`3.4-1ubuntu0.1`; configured history-limit is 50000. neither fact establishes
that retained scrollback caused the allocation. upstream's
[rgb redraw allocation fix](https://github.com/tmux/tmux/pull/4862) and
[follow-up](https://github.com/tmux/tmux/pull/4865) are investigation candidates,
not a verified diagnosis of this incident.

recovery observed at 16:27:21–22 utc: a new production tmux server pid 3117039
contained three sessions. the stock desktop client's authenticated production
inventory returned all three. the incident investigator performed no restart,
creation, closure or memory-policy change; recovery occurred during inspection.
this proves current terminal availability, not resumption of prior work.

fourth recurrence (2026-10-07): earlyoom terminated the webstorm remote backend
at 17:13:00 utc (pid 3737196, rss 1766 mib) and 17:46:36 utc (pid 3979685,
rss 2059 mib). the second kill occurred with 770/7751 mib ram available and
0/4095 mib swap free. the backend logged a clean shutdown at 17:46:37;
this was a userspace sigterm, not an ide crash or a connection timeout.
tailscale and ssh remained healthy, but gateway kept retrying the closed
backend port 5990 and the client displayed no connection.

inspect this incident with
`ssh dev-server-deploy 'sudo -n journalctl -u earlyoom --since "2026-10-07 17:10:00" --until "2026-10-07 17:50:00" --no-pager'`.
closing the disconnected remote window and reopening its recent ssh project
relaunches the backend, but does not resolve memory pressure.

after the kill, main tmux pid 3117039 held 2.61 gib rss and 3.56 gib swap.
its four panes reported only about 28 mb of history, so ordinary scrollback
alone does not explain its memory use; retained allocation or a leak remains
unproven. a separate notification qa tmux held about 452 mib rss and 175 mib
swap. these processes were preserved. establish why tmux retains this memory
and which qa fixtures are still needed before reclaiming them; restarting
tmux would interrupt its live sessions. restarting webstorm without more
headroom risks repeating the same termination.

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
