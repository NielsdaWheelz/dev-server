# codex mcp process leak

problem: the `~/.codex` app-server daemon starts mcp server processes for its
threads and never reaps them. they accumulate for as long as the daemon runs.

impact: on 2026-10-21 the daemon held about 210 idle processes using about
2.5 gib, and the count was still growing. that adds to host memory pressure until
the daemon restarts, and a restart interrupts every live session on that account.

evidence (2026-10-21, codex 0.163.0, daemon pid 7426, up about 4.5 days):
- two server kinds are direct children of the daemon. by evening there were 70
  of each, up from 68 that afternoon.
- `node_repl`, 646 mib rss: the `[mcp_servers.node_repl]` entry in
  `~/.codex/config.toml`. the `browser@openai-bundled` plugin's tools target it.
- `cua_node/bin/node .../@oai/cua-repl/bin/cua-repl.mjs`, 1,222 mib rss, each with
  one `node_repl` child (about 580 mib together): the `cua_repl` server that
  `unified-computer-use@openai-bundled` declares in its `.mcp.json`.
- working directories spread across nexus-web, hockey-stats, home, skidbladnir
  and jarvis. only four live tuis used that daemon at the time.
- the chatgpt app's codex integration installed these entries; dev-server does
  not manage them. the `~/.codex-work2` daemon had one such child;
  `~/.codex-work` had none.

2026-10-22 13:17, same daemon, up 5.2 days: 70 browser `node_repl` (677 mib), 71
`cua-repl.mjs` (1,337 mib) and their 71 `node_repl` children (936 mib), about
2.9 gib in all. one process more than the evening before, so growth tracks new
threads, not time. both kinds run from the chatgpt app's `cua_node/bin`, so
count by parent pid and arguments, not by binary path.

unverified: the exact lifecycle event that should release a thread's mcp
servers (turn end, tui detach, or thread unload), and whether managed-daemon mode
ever unloads threads.

reproduce: run several codex sessions against the daemon's `--remote` socket,
exit them, then count `node_repl` and `cua-repl.mjs` children of the daemon pid.

no thread identity: the processes' environment and arguments name no thread,
session or turn, so age relative to live sessions is the only way to pick out
stale ones. at inspection, 30 processes were older than the oldest live session
(19 h 24 min); the other ~110 could belong to live threads or their subagents.

decisions (operator, 2026-10-21): all plugins and mcp entries stay, and no
upstream report is sent. the cleanup is a daemon restart in each
[macbook capacity plan](../macbook-capacity-plan.md) window.

resolution: record the per-day growth after the first window's restart. the
record closes when an upstream release stops the accumulation.
