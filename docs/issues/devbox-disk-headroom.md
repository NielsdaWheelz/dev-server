# devbox disk headroom is low

problem: devbox has about 1.4 gb free after successful native maintenance, leaving
little room for builds, logs and future package operations.

evidence: the 2026-10-24 utc review found active user-owned rootless docker and
substantial developer storage. inactive system docker/containerd are separate
services. ownership and disposability of bulk storage are not established.

impact: ordinary growth can exhaust the root filesystem. this did not block the
completed native updates; nexus's 2 gib release floor does not apply to devbox.

resolved when a scoped ownership review identifies safe cleanup or a capacity
change and a fresh filesystem check establishes headroom for actual workloads.
preserve active containers, build work, caches and unrelated data until reviewed.
