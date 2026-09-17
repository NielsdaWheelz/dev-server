# move skid config validation upstream

problem: the installer duplicates skid's host configuration schema and deployment
profile details. changing a profile currently requires updating both the declared
json and shell validator.

impact: avoidable coupling slows configuration changes and risks schema drift.

evidence: the pinned v0.6.0 source (`2d6184c63d62396f69342200e4229cc902ca140c`)
has no standalone config validation command. `gateway` validates before serving
but starts a service; `agent-hook` deliberately suppresses configuration failures.
its host config loader also requires a fixed profile order and provider mapping.
neither command substitutes for admission before interrupting a healthy gateway.

resolved when: a pinned upstream release exposes a read-only config validator;
the installer invokes it before activation and drops its duplicated product
schema. keep deployment-owned path, credential, artifact, and ingress checks.

blocker: upstream validation command and a release containing it.
