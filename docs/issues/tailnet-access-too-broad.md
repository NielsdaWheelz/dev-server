# tailnet access is broader than required

problem: effective network filters on macbook, arch and devbox allow all ports
from tailnet addresses. production has not yet joined this network.

impact: an enrolled compromised device can reach unrelated services; adding
production unchanged would allow unnecessary lateral access.

evidence: 2026-10-23 read-only `tailscale debug netmap` inspection on all three
computers showed full-port destination ranges and broad tailnet source ranges.
this is effective-filter evidence, not a complete account-policy audit.

authenticated preflight subsequently confirmed the account policy grants all
sources to all destinations/ports and permits funnel for all members. the
supplied oauth credential exchanges successfully for owner-level api access;
no replacement token is needed. device inventory identifies both retirement
targets, but no device, grant or funnel permission has yet been changed.

resolved when the [security plan](../fleet-security-spec.md) device/port matrix
is implemented, its allow/deny tests pass, production cannot initiate peer
connections, and operator ssh plus every existing skid peer/client path works.
full account policy, device sharing and any active private memory consumers
must be inventoried first. implementation and live acceptance are NOT_RUN.
