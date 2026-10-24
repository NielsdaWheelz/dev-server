# macbook capacity plan

2026-10-21. specification only; nothing here has been applied. this plan owns
the cross-repo decisions for macbook capacity, the machine-level changes outside
any product repository, and the single maintenance window that applies the
disruptive steps. product repositories own their own specs and cite these
decisions by id.

## incident and evidence

on 2026-10-21 the macbook (m5 pro: 6 super cores, 12 performance cores in two
clusters, 64 gib) felt slow across skid, tmux, claude and codex. read-only
inspection between 15:28 and 16:10 local found:

- a nexus campaign session ran 24 `nice -n 19` cpu burners (`loaded.sh`,
  `BURNERS=24 REPEAT=20`). load average reached 147–162 and fell to 16 once the
  run ended. one six-core cluster sat at 100% while another idled near 14%.
- memory pressure level 2 (warn): 30 gib held by the compressor, 113 mib free,
  swap 4.25/5 gib. docker desktop's vm had a 24 gib footprint (5.3 gib resident,
  the rest compressed) while its containers used under 1 gib. colima profile
  `c3nt` (6 cpu, 12 gib) ran above one core for 1.5 hours. together the vms
  reserve 36 of 64 gib.
- docker desktop's vm process wrote 231 gb in 28 hours; colima wrote 17 gb in
  1.5 hours.
- skid serve's launchd job has no `ProcessType`. a launchd probe showed that
  absent or `Standard` gives children priority 20 and `Interactive` gives 31.
  serve starts the tmux server, so every agent, shell and tool call ran at 20,
  while ghostty login shells, the vms (31), docker's backend (46) and firefox (97)
  ran above them.
- skid's steady-state cost over 30 s: serve 13.6% of a core, its reaped tmux
  clients 17.5%, the tmux server 5.0%; serve had 770 wakeups/s.
- the `~/.codex` app-server daemon held 204 leaked mcp processes (~2.2 gib).
- interactive zsh rebuilt its completion cache whenever login and non-login
  shells alternated.
- ruled out: network (devbox 20 ms, provider apis ~40 ms), thermal limits, swap
  thrash, disk i/o throttling of the agent lineage.

## cross-repo decisions

repo specs cite these by id and do not restate or vary them. disagreements come
back here.

d1 runtime. docker desktop is the only container runtime on the macbook. no
repository uses colima. profile `c3nt` is deleted in the maintenance window after
its port session ends. hockey-stats has no container dependency; it deleted its
leftover docker stores on 2026-10-22.

d2 vm budget. docker desktop runs with 8 gib memory and 8 cpus. guest memory
the vm has touched stays with the host, resident or compressed, so the limit
becomes the steady-state footprint; it is sized to peak work, not headroom. two
lab stacks measured under 2 gib of container memory. the parallel-labs change
requires six full fake-provider labs on the unchanged 8 gib / 8 cpu allocation
and existing disk limit. qualification records actual overlapping product work,
host and container resources, pressure and abnormal exits. a measured capacity
blocker returns to the owner; it does not authorize a larger vm or a lower
accepted concurrency. exit 137 or a stalled lab requires diagnosis, including
whether the container was oom-killed.
the 24 gib setting of 2026-09-05 recorded no memory failure at 8 gib. the disk
image maximum (`DiskSizeMiB`, now 2 tib) drops to 128 gib in the window.
lowering it deletes the existing image, so this is a full docker reset. the
operator confirmed on 2026-10-22 that everything left in docker is disposable
dev, test and cache state, including jarvis's local postgres; images and stacks
rebuild on demand. the cap makes runaway image or cache growth fail builds
loudly instead of consuming the host disk.

d3 lab slots. nexus-web owns one host-wide lab capacity policy, defaulting to
six concurrent stacks. the optional
`${XDG_STATE_HOME:-~/.local/state}/nexus-lab/capacity.json` is a closed object
with sole key `max_parallel_labs`, for example `{"max_parallel_labs": 6}`;
nexus's runtime owns validation and admission. all worktrees use the same
absolute state home outside checkouts and docker binds.
ordinary labs take one slot; `--client-throttle N`, including `N=1`, takes all
configured slots so other labs cannot contaminate measurements. this excludes
other labs, not unrelated host work. change capacity only with labs, waiters and
owned runtimes drained. hard-cut old two-slot runners before activating the new
harness; there is no mixed-version admission protocol.

d4 load. "under load" proves that journeys survive a slow machine, meaning a slow
client. the instrument is per-page cpu throttling through playwright's cdp
session (`Emulation.setCPUThrottlingRate`). an optional slow-backend case adds
page network latency and may limit worker container cpus; the lab api runs on the
host, outside any cgroup, so latency is its only lever. no host-wide
cpu burners and no host load-average criterion. calibration: the instrument must
reproduce the base sha's known xfail before it replaces the burners. "survive"
means journeys complete without user-visible errors under timeouts scaled by the
throttle factor.

d5 harness ownership. campaign infrastructure (stack, slots, throttle, browser
helpers, verdict accounting) is owned, versioned code in nexus-web. journeys
remain temporary cases under nexus-web's 2026-09-17 reset.
`nexus-web-campaign-artifacts` holds run outputs only, never an implementation
that later campaigns copy.

d6 maintenance window. disruptive actions run once, operator-initiated, from the
runbook below. repo specs list what they need from the window and never require
ad-hoc restarts.

d7 priority. skid serve's launchd job declares `ProcessType=Interactive`, so
everything under skid's tmux runs at default priority (31) instead of the
standard-job clamp (20). the linux systemd unit is unchanged; agents share its
cgroup, so a weight there would throttle them too.

d8 cleanup ownership. tooling that creates images, volumes or networks removes
them in its own teardown. the one-time prune of existing leftovers happens in the
maintenance window.

d9 superseded guidance. each spec names the agent memory and notes that encode
superseded rules and updates or retires them with its change: the nexus claude
memory `project_macos_linux_runner_recipe.md` (docker sizing), the campaign
`design.md`/`decisions.md` ("docker desktop is never launched", the colima
requirement), and any similar records found.

d10 targets.
- machine: memory pressure level (`kern.memorystatus_vm_pressure_level`) stays 1
  through one campaign cycle plus interactive work.
- skid: at 18 panes with no browser or phone open, at most 1.5 tmux execs/s and
  under 5% of one core for serve, its reaped children and the tmux server,
  measured from `proc_pid_rusage` deltas over 30 s.
- nexus: no worker image rebuild when only application source changes; each
  invocation removes its owned runtime and preserves shared and peer images.

## owners

| concern | owner |
|---|---|
| nexus lab and campaign harness, load instrument, scoped teardown, lab slots, testing docs | nexus-web `docs/local-rules/testing-standards.md`; activation: `docs/issues/release-parallel-labs.md` |
| skid tmux exec budget and launchd `ProcessType` | skidbladnir `docs/tmux-exec-budget.md` and its issue records, branch `tmux-exec-budget-spec`; sequenced by skid's cleanup campaign |
| docker desktop sizing, colima retirement, codex mcp leak, zsh completion cache, the window | this plan |

## machine-level changes

### docker desktop sizing (d2)

set memory to 8 gib and cpus to 8 in docker desktop settings → resources during
the window, or set `MemoryMiB` and `Cpus` in `settings-store.json` while docker
is stopped; both were used on 2026-10-22. a nexus release-runner session
raised memory from the 8 gib default on 2026-09-05. dev-server does not declare
docker desktop settings: one drift in two months does not justify an apply
consumer with container-aware deferral. d9 retires the memory record that
prompted the raise. if drift recurs, declare `MemoryMiB` and the cpu key as
parser-backed keys under the existing `docker.config` deferral rule.

the window also lowers the disk image maximum to 128 gib (d2), which deletes and
recreates the image. the build cache already has a 20 gb cleanup limit in
`~/.docker/daemon.json`, but that limit only removes unreferenced cache. on
2026-10-22 docker reported 92 gb of build cache with only 20 gb reclaimable, and
244 images. the nexus image leak, not the limit, is what keeps the rest in use.

### colima retirement (d1)

`colima` and `lima` are homebrew formulae installed outside `packages/Brewfile`,
and the only profile is `c3nt`. once its port session has ended:
`colima delete --profile c3nt --data --force`, check that `limactl list` is empty,
`brew uninstall colima lima`, then remove `~/.colima` (43 gb) and
`~/Library/Caches/lima` (6 gb). the former hockey profile
lived on `/Volumes/Expansion` and was already deleted in hockey 03m.

### host disk

on 2026-10-22, after hockey's deletion returned about 96 gb, the data volume had
191 gib free of 926. `du` accounted for nearly all of the 744.5 gb consumed:

| holder | size | owner and disposition |
|---|---:|---|
| docker desktop (`Docker.raw`) | 178 gb | reset 2026-10-22 to a 128 gib maximum; 6.5 mb after |
| `~/.colima` plus `~/Library/Caches/lima` | 49 gb | removed 2026-10-22 |
| `~/.codex-personal` | 34 gb | deleted 2026-10-22 by operator decision: a former codex home, newest session 2026-09-05, with no path references |
| `~/.codex-default-archive-20260519`, `~/.codex-home-migration-backups` | 9.3 gb | deleted 2026-10-22 by operator decision: migration leftovers |
| `nexus-web-campaign-artifacts` | 33 gb | retired 2026-10-22 by nexus-web (#754) |
| regenerable caches | about 80 gb | optional: `~/Library/Caches/codapt` 18, `~/.cache/uv` 15, `~/.npm` 11, jetbrains 10, `go-build` 6, `~/.bun` 6, `~/.gradle` 4 |
| personal and hockey data | about 100 gb | operator: steam 61, android sdk and avds 19, `~/Backups/hockey-stats` 11 (protected by hockey-stats), claude desktop 10 |
| `/Applications`, `/Library`, homebrew, `/private/tmp`, `/private/var/folders` | 76 gb | system and transient |

after these removals the data volume had 444 gib free, against 191 that morning.
docker's rebuilt steady state will take some of it back, at most its cap.

### codex mcp process leak

recorded in [codex-mcp-process-leak](issues/codex-mcp-process-leak.md). upstream
codex owns daemon lifecycle (see the specification's codex daemon ownership).
operator decision, 2026-10-21: every plugin and mcp entry stays as configured,
and no upstream report is sent. a daemon restart, or skid's recovery restart of
tmux, which reconnects every tui, is the cleanup. nothing finer is exact,
because the leaked processes carry no thread identity.

### zsh completion cache

fixed and verified on 2026-10-24. the managed `assets/dotfiles/zshrc` adds homebrew's site functions to `fpath`
before `compinit`, so login and non-login shells agree on the file set. this
ships through ordinary apply as a `shell.config` change and needs no window.

## maintenance window runbook (d6)

run when no agent turn, lab stack or campaign is active. every step below
interrupts or deletes something.

1. preconditions. `docker ps` shows no `nexus-lab-*` or campaign stacks. the c3nt
   port session has finished, and nex-cleanup and the nexus host-budget runner are
   idle, because step 5 destroys every image and stack. codex sessions are daemon-owned (`--remote`) and
   claude conversations are resumable natively; skid recovery recreates the
   workspace and requests each saved conversation, but a turn in flight is lost.
2. skid priority (d7). the pin selects `v0.22.0`, whose installer writes
   `ProcessType=Interactive` and checks it. it is skid's lockstep cutover across
   three hosts and the phone ([runbook](gateway-separation-runbook.md)). pull
   dev-server, then run `./workstation gateway apply skidbladnir`, not the
   installed binary's `skid update`, which runs the old release's installer and
   writes its plist. check that
   `launchctl print gui/$(id -u)/dev.niels.skidbladnir` is running and that
   `ps -o pri= -p <serve pid>` prints 31.
3. tmux server restart. once serve has saved a schema-2 `workspace.json`, and
   with agent work stopped: stop the gateway, `tmux kill-server`, start the
   gateway. its same-boot recovery rebuilds the layout under a server it starts
   itself and requests each saved conversation through its profile's
   `resume_command` (skid `docs/session-recovery.md`). check that the new server
   and a fresh pane shell print priority 31.
4. codex daemons. with no turn running,
   `CODEX_HOME=~/.codex codex app-server daemon restart`; repeat for the work
   homes only if their leak counts warrant it. check that no `node_repl` or
   `cua-repl.mjs` process predates the restart.
5. docker desktop reset (d2). record `du -h` of
   `~/Library/Containers/com.docker.docker/Data/vms-data/Docker.raw` and
   `df -h /System/Volumes/Data`. in settings → resources, set memory to 8 gib,
   cpus to 8 and the disk image maximum to 128 gib, then apply. docker deletes
   and recreates its disk image. this replaces every prune and stale-stack
   removal. check that `docker system df` is empty and `docker info` reports
   the new memory and cpus. record both sizes again, then once more a day
   later.
6. colima. run the retirement steps above.
7. stale completion dumps. remove `~/.zcompdump`, `~/.zcompdump-*` and
   `~/.zcompdump.*`; the managed cache lives at `~/.cache/zcompdump`.
8. verify. memory pressure level 1 after docker restarts, then the acceptance
   list below. delete the records this window resolves.

### 2026-10-22 to 2026-10-24

steps 5–7 ran on 2026-10-22 and step 4 that night (operator, 23:21–23:22). steps
2, 3 and 8 ran on 2026-10-24 with skid v0.22.0; the window is complete.

- docker: a nexus runner set 8 gib and 8 cpus at 09:59 (nexus-web #751). at
  13:13 the reset ran with docker stopped: `DiskSizeMiB` set to 131072 in
  `settings-store.json` and `Docker.raw` deleted, so docker created a fresh
  128 gib image. nexus's storage cleanup (#754) had already removed every
  container and volume. before: 43 gb allocated, 399 gib free. after: 6.5 mb,
  444 gib free, `docker system df` empty, `NCPU=8`, `MemTotal` 8319770624.
- `docker desktop stop` reports failure while android emulators run, because it
  counts their qemu processes as its own, though its vm has stopped. `docker
  desktop start` then claims docker is running; `open -a Docker` starts it.
- colima: nexus deleted `c3nt` on 2026-10-21. `brew uninstall colima lima`
  also autoremoved the orphaned `usage` and `libngtcp2`; `brew bundle check`
  on `packages/Brewfile` still passes. `~/.colima`, `~/.lima` and
  `~/Library/Caches/lima` are removed.
- the stale `~/.zcompdump*` files are removed.
- skid: v0.22.0 on all three hosts and the phone. after the 13:04 recovery
  restart, serve, the tmux server and all 11 pane shells ran at priority 31, and
  recovery rebuilt the 11 saved sessions.
- zsh: after apply, alternating `zsh -ic exit` and `zsh -lic exit` left
  `~/.cache/zcompdump` byte-identical (`#files: 993`). the thrash record is
  deleted.
- memory pressure level 1 after these steps.

open from this plan: the six-lab qualification (d2, nexus-web), the macbook exec
measurement (d10, skid `tmux-exec-overhead.md`), docker's week-later allocation
([docker disk allocation](issues/docker-disk-allocation.md)) and the codex leak
([codex mcp process leak](issues/codex-mcp-process-leak.md)).

## acceptance

- memory pressure level 1 after docker restarts. six-way lab qualification keeps
  d2 fixed; a capacity failure remains an explicit unresolved blocker.
- docker's disk image maximum is 128 gib, and `Docker.raw` allocation and host
  free space are recorded before the reset, after it, and a day later.
- skid serve, the tmux server and pane shells run at priority 31.
- `colima` is absent and `docker context ls` shows only docker desktop.
- no codex mcp child predates its daemon's restart, and the leak's growth rate
  is recorded.
- after the zshrc change, alternating `zsh -ic exit` and `zsh -lic exit` leaves
  `~/.cache/zcompdump`'s header and mtime unchanged.

## out of scope

skid's fenced hub transfer and lagging fleet revisions (the operator handles
those separately), nexus's unexplained docker writes (nexus-web spec), and the
disposition of the operator-owned disk holders listed under host disk. declined on
2026-10-21: excluding
`~/Documents/code` from spotlight. inspection had found 32 `mdworker_shared`
processes and `mds_stores` averaging about 1% of a core.
