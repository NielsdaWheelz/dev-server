# skid phone-gateway cutover is not live

problem: dev-server pins skid v0.8.0 and installs herdr's codex and claude
integrations in place of skid's cli, hooks, notifier, plugin and the devbox's
`/usr/local/libexec/skidbladnir` copy (pr 5 step 4); devbox and the macbook
applied it on 2026-09-24, arch has not (it is down).

impact: arch keeps its old release and skid's hooks until its apply. v0.7.0 and
v0.8.0 reject each other's host config, so the pin, host config and integration
switch land together in one apply per host.

evidence (2026-09-24): disposable darwin qualification of the rebased step 4
tip (`d7ef936`) with the v0.8.0 draft's darwin archive: main to branch transition, a second
apply unchanged, one phone launch per profile with its account home, rollback
to main and forward again. linux, the ansible path, real providers and the
phone app were not exercised. deployed jarvis `39d9c9c` already controls
workers through herdr over ssh.

v0.8.0 was published on 2026-09-25 with `SHA256SUMS` byte-identical to the
draft the pin names.

2026-09-24 window (`db32035`): devbox applied with jarvis paused and stopped
(v0.8.0, previous v0.7.0, v0.6.0 pruned; integrations current in all five
homes; the libexec copy removed); the macbook applied (v0.8.0, herdr's hooks
replaced skid's, tmux reloaded once for #125). codex's hook-trust prompt was
answered once per account home on both hosts after checking every hook is
herdr's: `work`/`work2` load `~/.codex/hooks.json` as project config when the
working directory is `~`, so they show two hooks. devbox's `work`/`work2` first
offered codex's update with `Update now` preselected; skipped until the next
version. `fleet verify` passes for macbook and devbox. the phone runs 8000,
installed in place, and shows both. jarvis `39d9c9c` resumed.

follow-up: apply arch when reachable and answer its hook-trust prompts; then,
with v0.8.0 accepted on all three, remove the residue in
[skid-cli-retirement](skid-cli-retirement.md).

resolved when: every host runs v0.8.0 with `herdr integration status` current
for codex and claude in each account home, the phone lists, launches per
profile, streams, interrupts and stops with its existing pairings, and jarvis's
herdr control works.
