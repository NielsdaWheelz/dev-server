# codex daemon disk i/o

problem: each codex account daemon on the macbook did tens of gigabytes of disk
i/o over four days. the source is unknown.

impact: unexplained ssd wear and i/o contention. it may point to repeated
rewrites of session state or rollouts.

evidence (2026-10-21, `proc_pid_rusage` lifetime counters, codex 0.163.0, each
daemon up about 4.4 days):

| daemon | written | read |
|---|---|---|
| `~/.codex` (pid 7426) | 17.8 gb | 38.2 gb |
| `~/.codex-work` (pid 4237) | 17.8 gb | 45.8 gb |
| `~/.codex-work2` (pid 93073) | 14.9 gb | 37.2 gb |

a 20 s sample during light use showed 0.0–0.6 mb/s, so the volume comes in
bursts.

reproduce: sample `ri_diskio_byteswritten` and `ri_diskio_bytesread` for a
daemon pid before and after a single long turn, alongside the size growth of
that account's `sessions/` rollouts and state database.

resolution: attribute the i/o to specific files and operations. then either
accept it as proportional to session activity or report it upstream with that
evidence.
