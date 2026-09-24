# herdr library dies under bash 3.2 on an empty socket array

problem: `lib/herdr.sh` `herdr_render_session_sockets` expands `"${sockets[@]}"`
under `set -u`. macos's `/bin/bash` 3.2 treats an empty array expansion as an
unbound variable and aborts with `sockets[@]: unbound variable`; bash 4+ does
not.

impact: none in production. `./workstation` and the library recipes resolve
`#!/usr/bin/env bash` to homebrew bash 5, where the expansion is fine. anyone
sourcing the library under `/bin/bash` dies before any mutation, so the failure
is loud and safe, but it is a portability defect, not a design choice.

evidence (2026-09-23): observed while running the disposable darwin
qualification recipe under `/bin/bash`; present at `8990817` (`lib/herdr.sh`
297, the loop over `sockets`).

resolved when: the loop guards the empty case (`${sockets[@]+"${sockets[@]}"}`)
or the scripts state bash 4 or newer as a requirement where they state the
interpreter, and the recipe runs under `/bin/bash -n` plus one sourced call
without the error. delete this file with that change.
