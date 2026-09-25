# rootless docker rebuilds installation for ordinary config changes

problem: the rootless role hashes daemon config, package version and generated
unit into one identity. any mismatch invokes the native setup tool's uninstall
and install, even when only log policy changed.

impact: routine configuration activation deletes/recreates the unit and cli
context, adding failure points and repeated setup validation.

evidence (2026-09-25): a disposable fixture ran the role's actual repair shell
with an existing active idle service. it called `--force uninstall` followed
by `--force install`. the installed upstream setup script confirms uninstall
stops/disables the service, removes its unit and deletes its cli context.
the role's config checksum participates in the mismatch predicate.

follow-up: separate initial setup/repair from daemon activation. a config-only
change needs safe activation, not installation teardown. retain the immediate
container check and persistent pending-activation proof. qualify package-driven
unit changes explicitly; do not assume generated units never change.

resolved when: changing log policy leaves unit/context installation intact,
idle services activate it, busy services defer, and missing/broken setup still
repairs through the native tool. reference: `ansible/roles/rootless_docker/tasks/main.yml`.
