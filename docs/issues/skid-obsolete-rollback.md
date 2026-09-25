# skid retains a retired rollback baseline

problem: the live devbox's previous pointer still names v0.6.0, while the
supported rollback boundary is herdr-era v0.7.0 or later. the specification
also contradicts itself about retaining the old native-control helper.

impact: retained files suggest a rollback capability whose complete operational
dependencies have been retired. no running-gateway failure was observed.

evidence (2026-09-25): current points to v0.7.0 and previous to
v0.6.0-6ea3ae84d2e38091d9e15e8d39f8983db114ac696b30674777a517ac9e403999.
`SPEC.md:349-351` retires that rollback; `SPEC.md:470-471` preserves helpers for it.

follow-up: retire the unsupported generation/helper baseline and contradictory
wording. retain a complete verified herdr-era prior activation where available;
do not manufacture rollback evidence by renaming a pointer.

resolved when: installed retention and documentation agree on the supported
rollback boundary, with no obsolete helper retained for v0.6.0.
