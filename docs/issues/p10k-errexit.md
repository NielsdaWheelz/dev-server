# powerlevel10k and interactive errexit

problem: a full themed zsh shell exited after a nonzero test provider while
`errexit` was enabled. skid printed the correct status; its callback explicitly
ends with return zero. theme widget processing subsequently recorded status 1 at
`_p9k_deschedule_redraw`.

impact: full themed-shell survival after provider failure under errexit remains
unqualified. the managed startup configuration does not enable errexit.

evidence, 2026-09-29: a temporary controlling-pty fixture with the managed zsh
stack and theme pin `3308262dfbd743b6e1d3956a2b5572f7a049d692` recorded
status 1 at this function and shell exit after a provider returned 37. an
ordinary-shell probe with a successful command did not reproduce that exit.
the precise interaction remains unresolved; skid's direct callback matrix
under errexit is narrower.

resolved when: establish the supported interactive option contract with
powerlevel10k and qualify the nonzero-provider journey, repairing the failure
at its responsible layer. do not infer a provider launch failure or suppress
nonzero commands globally.
