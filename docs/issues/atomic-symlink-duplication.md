# dotfiles duplicates the shared atomic symlink operation

problem: `dotfiles_atomic_symlink` duplicates `dev_server_atomic_symlink`, with
reversed arguments. both stage a link and atomically replace its destination.

impact: one filesystem primitive has two maintenance owners.

evidence (2026-09-25): `lib/dotfiles.sh:117-142` has one caller at line 218;
`lib/common.sh:688` already supports absolute targets, idempotence, cleanup and
atomic replacement. dotfiles separately verifies its managed link's ownership.

follow-up: call `dev_server_atomic_symlink "$dest" "$generation"` and remove
the duplicate helper. retain dotfiles' product-specific ownership checks.

resolved when: one primitive handles both uses, with identical installed links,
safe failure on conflicting files and no writes on an unchanged apply.
