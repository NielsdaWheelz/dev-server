# arch's herdr machines and gate

problem: arch was down when herdr pr 5 step 1 landed. arch has no gate,
authorized jarvis key, saved machines or respecting `codex` wrapper, and none
of its ssh edges is proven.

impact: `herdr --machine macbook|devbox` fails from arch, `herdr --machine
arch` may fail from the macbook, and jarvis cannot reach arch through the gate.

evidence: 2026-09-24, arch unreachable. arch's ed25519 host key in
`assets/herdr/jarvis-known_hosts` was copied from the macbook's
`~/.ssh/known_hosts` (`ssh-keygen -F arch`), not read from arch.

needed, on arch: `./workstation apply` with jarvis's key committed; arch's user
key authorized for `nnandal` on the macbook and `niels` on devbox; the
macbook's and devbox's host keys in arch's `~/.ssh/known_hosts` under the saved
targets' names, `niels-eriks-macbook-pro` and `dev-server` (confirm that
`dev-server` resolves on arch). from the macbook, `nnandal@arch` must accept
the macbook's key.

resolved when: arch's `/etc/ssh/ssh_host_ed25519_key.pub` equals the `arch`
line in `jarvis-known_hosts`; `herdr --machine macbook agent list` and
`herdr --machine devbox agent list` succeed on arch; `herdr --machine arch
agent list` succeeds on the macbook; on devbox, jarvis's
`ssh -F /etc/jarvis-herdr/ssh_config arch agent list` prints herdr's json and
`ssh -F /etc/jarvis-herdr/ssh_config arch pane run x y` is refused. delete this
file then.
