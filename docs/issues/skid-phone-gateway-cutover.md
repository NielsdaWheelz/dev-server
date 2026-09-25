# skid phone-gateway cutover is not live

problem: dev-server pins skid v0.8.0 and installs herdr's codex and claude
integrations in place of skid's cli, hooks, notifier, plugin and the devbox's
`/usr/local/libexec/skidbladnir` copy (pr 5 step 4), but no host has applied it.

impact: each host keeps v0.7.0 and skid's hooks until its apply. v0.7.0 and
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

follow-up: apply devbox and both workstations; answer codex's one-time hook-trust prompt
per account; install the v0.8.0 app once every gateway runs v0.8.0; then
remove the residue in [skid-cli-retirement](skid-cli-retirement.md).

resolved when: every host runs v0.8.0 with `herdr integration status` current
for codex and claude in each account home, the phone lists, launches per
profile, streams, interrupts and stops with its existing pairings, and jarvis's
herdr control works.
