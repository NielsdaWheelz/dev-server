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

unverified: the exact lifecycle event that should release a thread's mcp
servers (turn end, tui detach, or thread unload), and whether managed-daemon mode
ever unloads threads.

reproduce: run several codex sessions against the daemon's `--remote` socket,
exit them, then count `node_repl` and `cua-repl.mjs` children of the daemon pid.

decisions (operator, 2026-10-21): the browser is unused, so the
[macbook capacity plan](../macbook-capacity-plan.md) window removes the
`node_repl` entry and disables the browser plugin. computer use stays, so its
`cua_repl` leak continues and each later window's daemon restart clears it. no
upstream report is sent.

resolution: after a week of normal use following the window, the daemon has no
`node_repl` child, and the `cua_repl` growth rate per day is recorded here. the
record closes when an upstream release stops `cua_repl` accumulating.
