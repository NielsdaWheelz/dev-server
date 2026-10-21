# standalone skid release and installed cutover

problem: the standalone consumer pins reviewed published terminal-only `v0.20.0`
from `acf4e1770b03fe254d201fdcd9cc7add0cce79ad`, but its authorized installed
three-host/phone cutover has not yet run.

impact: no standalone host/phone activation can be claimed. the old deployed
runtime remains unchanged; incompatible old archives cannot satisfy this source.

evidence, 2026-10-20: public bootstrap hash, both host signatures and exact
release manifests pass. temporary fixtures qualify installer delegation,
whole-file hub yaml ownership, startup-block preservation and refusal boundaries;
the probes are removed. copied skid runtime/ntfy/helper/services are removed
from source. linux installed ownership validators and read-only baselines pass;
these do not establish activation or parity.

resolution: upgrade macbook, devbox, arch and the phone in place. preserve the
existing machine handles/order, devbox hub, pairings, observer state and device
acknowledgements; do not reset the fleet or pair again. change only the four
private desired-yaml command values to `codex`, `codex-work`, `codex-work2` and
`claude-work`, preserving all other bytes and mode `0600`, then apply the signed
configuration. qualify the matching host/phone terminal, quota and notification
contracts while preserving settings/history, active tmux and existing provider
lifetimes, including the running mac claude process. no account-daemon lifecycle
work belongs to this cutover. clean only the verified deployment-owned identity
plugin files under the [runbook's cleanup boundary](../gateway-separation-runbook.md#provider-and-jarvis-contract),
retaining immutable skid installation generations. jarvis remains STOPPED pending
its separate recorded service-state access work.

source qualification removed identity-plugin publication and made the four
command values plain. isolated apply twice with private override present/absent
passes; unrelated private values/mode survive. temporary consumer probes were
removed after integrator review and retained evidence.

evidence, 2026-10-21: the immutable public `v0.20.0` release and matching exact
source/bootstrap pin are available. private desired-yaml changes, verified
plugin cleanup and host/phone activation remain separate. the owner authorized
keeping the existing mac claude process running during removal of the exact
verified `SessionStart`-only identity plugin whose failure does not block claude;
preserve immutable skid installation generations. jarvis remains STOPPED pending
its separate service-state access work. no new privilege bridge or copied state
is authorized.
do not count fixture convergence or release publication as installed acceptance.
