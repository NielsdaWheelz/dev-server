# codex mcp process leak

problem: the `~/.codex` app-server daemon starts mcp server processes for its
threads and never reaps them. they accumulate for as long as the daemon runs.

impact: on 2026-10-21 the daemon held 204 idle processes using about 2.2 gib.
that adds to host memory pressure and grows without bound until the daemon
restarts. restarting it interrupts every live session on that account.

evidence (2026-10-21, codex 0.163.0, daemon pid 7426, up 4 days 9 hours):
- 68 `node_repl` processes are direct children of the daemon (1,640 mib rss,
  counted together with the next item).
- 68 `cua_node/bin/node .../@oai/cua-repl/bin/cua-repl.mjs` processes are also
  direct children, each with one `node_repl` child (583 mib rss for those
  children).
- their working directories spread across nexus-web (76), hockey-stats (44),
  home (7), skidbladnir (6) and jarvis (4).
- only four live tuis used that daemon at the time.
- `~/.codex/config.toml` declares `[mcp_servers.node_repl]` with command
  `/Applications/ChatGPT.app/Contents/Resources/cua_node/bin/node_repl`, plus the
  `browser`, `computer-use` and `unified-computer-use` bundled plugins. the
  chatgpt app's codex integration added these; dev-server does not manage them.
- the `~/.codex-work2` daemon had one such child; `~/.codex-work` had none.

unverified: the exact lifecycle event that should release a thread's mcp
servers (turn end, tui detach, or thread unload), and whether managed-daemon mode
ever unloads threads.

reproduce: run several codex sessions against the daemon's `--remote` socket
that touch the node repl or browser tools, exit them, then count `node_repl` and
`cua-repl.mjs` children of the daemon pid.

upstream report draft (not sent): "codex app-server --managed-daemon 0.163.0 on
macos keeps per-thread mcp server processes after their sessions end. after 4
days, one daemon had 68 node_repl and 68 cua-repl.mjs children (~2.2 gib), while
4 sessions were live. expected: a thread's mcp servers exit when the thread is
unloaded or its last client detaches. repro: [steps above]."

resolution: either configuration removes the leaking servers, or upstream fixes
the lifecycle. after a week of normal use, the daemon has no mcp child older
than its oldest live thread. until then, the window in the
[macbook capacity plan](../macbook-capacity-plan.md) restarts the daemon.
