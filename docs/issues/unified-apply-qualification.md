# unified apply needs native qualification

problem: unified apply is implemented, but installed native supervision and real
provider behavior remain incompletely qualified. the mac terminal-runtime cutover
remains held.

impact: source checks do not establish installed fleet behavior. daemon updates
can interrupt work; a running version does
not prove clients reconnected or cold configuration was loaded.

evidence: signed immutable skid v0.24.1 at source
`8bb07e88e039a9aaf24347acaceb322132de67e6` passed public artifact verification.
bootstrap `12d25144238f5b9ee0f2fe0c3441daaebb0cd103` is public and its downloaded
bytes match the declared checksum. disposable fixtures exercised the provider adapter, result transport,
consumer and activation paths. an isolated ubuntu arm64 container exercised a real
systemd user supervisor with fake providers. these checks do not qualify real
provider accounts. supported linux amd64 and arch native supervisors, macos
native job supervision, real provider update and client reconnection are not_run.

resolution: separately qualify target-local macos, linux amd64 and arch supervision and real provider
update/reconnection on the owned hosts with current owner authorization. demonstrate success, pending or
unknown outcomes, cleanup and non-replay at the native boundaries; record any
remaining limits. qualify the held terminal-runtime cutover separately.
