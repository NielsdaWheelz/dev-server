# arch's jarvis gate

problem: arch was down when herdr pr 5 step 1 landed. it has no
`~/.local/libexec/herdr-gate`, no authorized jarvis line and the old `codex`
wrapper.

impact: jarvis cannot reach arch's herdr, and a codex pane created there for a
work account would still run personal.

evidence: 2026-09-24, arch unreachable. arch's ed25519 host key in
`assets/herdr/jarvis-known_hosts` was copied from the macbook's
`~/.ssh/known_hosts` (`ssh-keygen -F arch`), not read from arch.

needed: once arch is up and jarvis's key is committed, `./workstation apply` on
arch. human ssh from arch to the macbook or devbox is only ssh keys and known
hosts now, the owner's to set up if wanted; dev-server manages none of it.

resolved when: arch's `/etc/ssh/ssh_host_ed25519_key.pub` equals the `arch`
line in `jarvis-known_hosts`, and on devbox, as jarvis,
`ssh -F /etc/jarvis-herdr/ssh_config arch agent list` prints herdr's json while
`ssh -F /etc/jarvis-herdr/ssh_config arch pane run x y` is refused. delete this
file then.
