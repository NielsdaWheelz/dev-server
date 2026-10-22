# zsh completion cache thrash

problem: login and non-login interactive zsh disagree about `fpath`, so they
invalidate each other's completion dump. homebrew's `.zprofile` line
`eval "$(/opt/homebrew/bin/brew shellenv zsh)"` adds
`/opt/homebrew/share/zsh/site-functions` in login shells only. the managed
`zshrc` runs `compinit -d ~/.cache/zcompdump` in both modes. compinit reuses a
dump only when its `#files:` header matches the current count.

impact: whenever a login shell follows a non-login one, or the reverse,
`compinit` rescans every completion file and rewrites the dump. that cost about
2 s per shell under load, instead of about 0.6 s. new panes, skid starts and
tools that spawn interactive shells pay it.

evidence (2026-10-21, macbook): the dump header read `#files: 1022` after login
shells and `#files: 994` after non-login ones. its mtime changed on every mode
switch and stayed put between same-mode shells. same-mode repeats took
534–673 ms; the first shell after a switch took 2,397–2,629 ms. `zprof` on a
rebuild attributed 611 ms to `compinit` (822 `compdef` calls, 112 ms `compdump`)
and 169 ms to `_mise_hook`. 14 stale `~/.zcompdump*` files from older
configurations remain in home.

resolution: the managed `zshrc` places homebrew's site functions on `fpath`
(deduplicated with `typeset -U fpath`) before `compinit`, so both modes see the
same file set. alternating `zsh -ic exit` and `zsh -lic exit` then leaves the
dump's header and mtime unchanged after the first run. the stale dumps are
removed in the [macbook capacity plan](../macbook-capacity-plan.md) window.
