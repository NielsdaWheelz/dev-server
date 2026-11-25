# arch antigravity installation

on 2026-11-25 tailscale reported arch offline and ssh to `arch` timed out.
the shared apply path is ready. arch's antigravity and gemini cli installations
could not be inspected.

close after arch is reachable, `./workstation apply` with the antigravity change
reports an `agy` result, and a fresh login shell resolves `agy` to
`~/.local/bin/agy` and runs `agy --version`. check for gemini cli and remove it
manually if installed. resolve any command conflicts manually.
