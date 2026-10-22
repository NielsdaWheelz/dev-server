# zsh completion cache thrash

status: the source fix is in `assets/dotfiles/zshrc`. the record stays open
until apply installs it on the macbook and the live check below passes.

problem: compinit reuses `~/.cache/zcompdump` only while its `#files:` header
matches the current count of completion files on `fpath`, and that count
differed by shell mode. homebrew's `.zprofile` line
`eval "$(/opt/homebrew/bin/brew shellenv zsh)"` runs `fpath[1,0]=...` and
prepends `/opt/homebrew/share/zsh/site-functions` unconditionally:
- a login shell that inherits an exported `FPATH` already containing that
  directory lists it twice, so compinit counts its 28 files twice (1,022 vs 994).
- a non-login shell with no inherited `FPATH` lacks it entirely (966 vs 994).

either way, alternating modes rewrote the dump on every switch.

impact: each rewrite rescans every completion file. that cost about 2 s per
shell under load, instead of about 0.6 s. new panes, skid starts and tools that
spawn interactive shells pay it.

evidence (2026-10-21, macbook):
- the live dump header read `#files: 1022` after login shells and
  `#files: 994` after non-login ones. its mtime changed on every mode switch and
  stayed put between same-mode shells.
- same-mode repeats took 534–673 ms; the first shell after a switch took
  2,397–2,629 ms.
- `zprof` on a rebuild attributed 611 ms to `compinit` (822 `compdef` calls,
  112 ms `compdump`) and 169 ms to `_mise_hook`.
- 14 stale `~/.zcompdump*` files from older configurations remain in home.

fix: before `compinit`, the managed `zshrc` runs `typeset -U fpath` and
prepends the homebrew directory when it exists. a temporary test ran each zshrc
under its own `ZDOTDIR` and `XDG_CACHE_HOME`, alternating `-ic` and `-lic`:

| zshrc | inherited `FPATH` | none |
|---|---|---|
| before | headers 994/1022, rewritten every run | headers 966/994, rewritten every run |
| after | 994 throughout, reused after the first run | 994 throughout, reused after the first run |

resolution: after apply, alternating `zsh -ic exit` and `zsh -lic exit` on the
macbook leaves the dump's header and mtime unchanged after the first run. the
stale dumps are removed in the [macbook capacity plan](../macbook-capacity-plan.md)
window.
