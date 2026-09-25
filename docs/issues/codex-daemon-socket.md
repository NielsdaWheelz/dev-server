# codex 0.156 app-server socket

problem: codex 0.156 binds `app-server --listen unix://PATH` to a socket under
`/tmp/codex-daemon-UID/<sha256>` (directory 0700) and publishes `PATH` as a
symlink to it. `codex-shared.py grant-socket` requires a socket at `PATH` and
exits, and a client in `codex-clients` cannot traverse the 0700 directory.

impact: on the devbox the three `codex-shared@*` services fail to start and
jarvis loses cognition and its live catalog, so it cannot serve or pass
`check-activation`. the devbox pins codex 0.155.1 in `ai_install_codex`; an
upgrade past it reproduces the failure, and so does codex's own startup prompt:
each new release offers `Update now` preselected (it runs `npm install -g
@openai/codex`). herdr reads that menu as `blocked`, so an ordinary send is
refused, but a terminal-mode enter or a hand at the keyboard installs it. on
2026-09-24 the devbox personal profile skipped 0.156.1 "until next version".

evidence (2026-09-24): the isolated linux qualification of skid pr 4 started
`codex-shared@personal` with codex-cli 0.156.1: `status=1/FAILURE` restart loop;
jarvis through the symlink got `Errno 13` (jarvis
`docs/qualification/2026-09-23-herdr-pr4.md`, row "real codex app-server"). the
macbook's services under 0.156.1 published the same symlinks and
`./workstation apply` failed `shared Codex socket ownership or permissions
differ`; workstations no longer run shared servers.

resolved when: jarvis runs its own codex process and the devbox services are
deleted, or a codex release binds the declared path again and the devbox runs it with
`codex-shared@*` active and jarvis's `verify-containment` passing; then remove
the pin.

blocker (2026-09-24): jarvis's current specification requires the shared
runtime and its operations guide forbids starting a private app server. the
previously linked `jarvis/docs/issues/codex-private-process.md` is absent from
the checked-out jarvis repo. retiring shared services requires changing that
consumer contract first.
