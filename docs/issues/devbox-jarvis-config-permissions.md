# devbox apply would revoke jarvis memory access

on 2026-11-20, `/etc/jarvis` on devbox was `root:jarvis-memory` with mode
`0710`. the active `jarvis-memory` service runs under that group alone. the
jarvis release installer sets these permissions so the service can reach
`/etc/jarvis/memory.json`.

the `jarvis_host` role sets the directory to `root:jarvis` with mode `0750`.
the devbox playbook also requires that value in its final check. applying the
role would prevent the memory service from traversing the directory on its
next read. the codex update used the host's codex maintenance steps directly.

resolve when a full devbox apply preserves the installed release's directory
permissions and `sudo -u jarvis-memory test -r /etc/jarvis/memory.json` passes
afterward. verify initial provisioning on a fresh host as well.
