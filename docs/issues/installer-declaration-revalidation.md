# local declarations repeat themselves in preflight checks

problem: dotfiles and personal arch/macos preflight duplicate file lists solely
to check regular source files. the common atomic installer checks the same
property at consumption.

impact: changing one declaration requires editing a second representation;
these checks add no whole-host transaction, which the specification disclaims.

evidence (2026-09-29): `dotfiles_validate_declared_inputs`,
`personal_arch_validate_declared_inputs` and
`personal_macos_validate_declared_inputs` repeat source-file checks in their
owning libraries; `lib/common.sh` validates inputs again at atomic installation.

follow-up: each installer should own validation at consumption. remove only
existence-only secondary lists; retain native parser checks and actual
cross-component constraints.

resolved when: an asset edit has one policy owner, invalid consumed input still
fails at the owning boundary, and genuine session/identity constraints remain.
