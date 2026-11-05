# unified apply needs native qualification

problem: unified apply is implemented, but no qualifying signed skid release
containing its action-required exit contract is published. the reviewed bootstrap
commit `12d25144238f5b9ee0f2fe0c3441daaebb0cd103` is publicly reachable and its
downloaded bytes match the declared checksum. the
mac terminal-runtime cutover remains held.

impact: source checks do not establish installed fleet behavior. do not merge or
deploy this integration until the bootstrap and qualifying signed release are
public and verified. daemon updates can interrupt work; a running version does
not prove clients reconnected or cold configuration was loaded.

evidence: disposable fixtures exercised the provider adapter, result transport,
consumer and activation paths. an isolated ubuntu arm64 container exercised a real
systemd user supervisor with fake providers. these checks do not qualify real
provider accounts. supported linux amd64 and arch native supervisors, macos
native job supervision, real provider update and client reconnection, and the
public signed skid release are not_run.

resolution: verify the public bootstrap hash and signed release, then separately
qualify target-local macos, linux amd64 and arch supervision and real provider
update/reconnection on the owned hosts with current owner authorization. demonstrate success, pending or
unknown outcomes, cleanup and non-replay at the native boundaries; record any
remaining limits. qualify the held terminal-runtime cutover separately.
