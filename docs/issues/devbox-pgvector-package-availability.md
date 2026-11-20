# fresh devbox cannot fetch the pinned pgvector build

devbox pins `postgresql-16-pgvector=0.8.6-1.pgdg24.04+1`. on 2026-11-20 the
configured `noble-pgdg` amd64 index listed `0.8.6-1.pgdg24.04+2` and two
`0.8.7` builds. a new host needs another source for the pinned build.

the official `noble-pgdg-archive` amd64 index still lists the exact package.
the permissions rehearsal supplied that signed archive in the disposable guest.
[postgresql package archive](https://apt-archive.postgresql.org/)

resolve when a fresh ubuntu 24.04 amd64 host can install and hold the qualified
build using only the package sources declared by dev-server.
