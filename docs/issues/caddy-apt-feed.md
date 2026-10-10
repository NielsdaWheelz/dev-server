# caddy package feed blocks devbox apply

problem: the pre-existing caddy apt source prevents a complete devbox apply.
the feed is not declared by this repository.

impact: apt cache refresh fails before declared packages and later roles can
converge. tmux maintenance can still install its build dependencies from the
available ubuntu indexes and apply the workspace assets and shell roles.

evidence: on 2026-10-09, `./devbox apply` failed after five cache refresh retries.
`https://dl.cloudsmith.io/public/caddy/stable/deb/debian/dists/any-version/InRelease`
returned `402 Payment Required`; apt consequently rejected the repository as
unsigned. the source is `/etc/apt/sources.list.d/caddy-stable.list`, last modified
2026-05-27. no source or signature policy was changed during tmux maintenance.

reproduction: run `./devbox apply`, or `sudo apt-get update` on devbox.

resolution: establish the owner and supported replacement for this caddy source,
restore a successful signed apt cache refresh, then complete `./devbox apply`.
