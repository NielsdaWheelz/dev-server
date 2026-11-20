# caller path drift triggers macbook terminal replacement

on 2026-11-13, macbook apply reported `tmux sessions are still running`
while skid was checking whether its terminal runtime needed replacement.
provider installation, the three codex daemon checks and the fleet configuration
update had completed.

the installed terminal app's three files matched the verified skid `v0.24.2`
release archive at source `d4afbfcec963b1f231fc117675120eff1685e881`.
the installed service had a short explicit path. a fresh login shell added
mise shims and other entries. that difference alone requests replacement on
an unchanged release. the original caller's environment was not captured.

in skid `v0.27.0`, `internal/install/services.go` still copies `os.Getenv("PATH")`
into the service definition. `runtimeChanged` in `internal/install/terminal.go`
compares its rendered bytes with the installed file. ordinary reapply can
therefore request terminal downtime whenever the invoking shell's path changes.

resolve in skid's installer by giving the service a stable path. verify that
changing the caller's path preserves the running terminals and that a change
to the runtime or its declared service settings still requires maintenance.
