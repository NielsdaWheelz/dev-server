# retire skid's old worker cli and integration installation

problem: dev-server still installs skid v0.7.0's worker cli, identity hooks,
notifier, claude plugin and a root-owned cli copy for jarvis. deployed jarvis
already controls workers through herdr over ssh. the next skid release removes
the old interfaces.

impact: the jarvis cli copy has lost its current consumer; remaining integration
machinery is tied to the old gateway release and has a planned replacement.

evidence (2026-09-25): deployed jarvis `39d9c9c`,
`src/jarvis/agent_control.py:245`, invokes `/usr/bin/ssh`. skid main
`7680c556` merged the phone-only gateway. release inspection found v0.8.0
still draft and v0.7.0 latest published. upstream `docs/herdr-pr5.md`, delivery
step 4, specifies the corresponding dev-server deletions and native herdr
integration installation. `SPEC.md:219` still describes worker control through
skid's peer cli and needs updating with that cutover.

follow-up: qualify and publish the upstream release, then pin it and remove the
skid link, hooks, notifier, plugin and `/usr/local/libexec/skidbladnir` copy.
install herdr's native account integrations in the same cutover: both writers
touch hook/settings files. retain account instructions and the herdr ssh gate.

resolved when: the published gateway preserves phone journeys/pairings and
jarvis's herdr control works; old cli/integration files are absent and only the
native integration owner manages those hooks. no unpublished pin or live
cutover was attempted during this audit.
