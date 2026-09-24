# herdr saved machines

problem: herdr 0.9.1's saved machines (`~/.local/state/herdr/client/endpoints.json`,
`herdr --machine <label>`) are not used. every interactive herdr client with an
enabled saved machine keeps an ssh session to it and reconnects with backoff
(`src/client/mod.rs:200-215`, `src/client/endpoint/supervisor.rs`). the remote
end is `herdr remote-client-bridge`, which runs `herdr server` itself when no
server listens (`src/remote/host.rs:38-60`). that unmanaged server would take
the socket while dev-server's supervised one is stopped for a pin change or a
restart, or before it starts on arch's login, and apply then reports an
unmanaged socket. 0.9.1 has no attach-only or no-spawn switch for the bridge.

impact: no `herdr --machine`. humans use `herdr --remote <ssh-target>` (same
bridge, but only when invoked, so not during a stop window) and
`ssh <host> herdr <command>`, whose api commands never start a server. jarvis
uses its gate and is unaffected.

evidence: herdr source at the pinned `065ef9d6`, read 2026-09-24.

resolved when: a herdr release lets the bridge (or saved machines) refuse to
start a server, or dev-server's supervisor can own a server that herdr started.
then save the machines declaratively again, with each edge's keys and known
hosts, and delete this file.
