# an account wrapper change requires daemon drain

problem: `codex-shared.py` both renders human account wrappers and implements
the shared daemon boundary. codex's operational identity hashes the whole file
and the shell zshenv, so unrelated wrapper edits require restarting all servers.

impact: a launcher-only change requires a jarvis maintenance window.

evidence (2026-09-25): `ansible/playbooks/tasks/codex-runtime-preflight.yml:84`
hashes the helper. upstream skid's `docs/herdr-pr5.md`, delivery step 1,
explicitly required `--restart-codex` during jarvis's stop window for the
respect-preset-account wrapper change.

follow-up: delete this coupling with shared-runtime retirement described in
`codex-daemon-socket.md`. if that migration waits, separate pure wrapper
rendering from daemon operational inputs. do not weaken the daemon's actual
configuration activation checks.

resolved when: a wrapper-only edit installs without draining shared servers;
real server-input changes still require their intended activation decision.
