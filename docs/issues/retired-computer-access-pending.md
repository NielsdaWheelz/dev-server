# retired computer access still needs revocation

problem: `skq-linux` and `niels-desktop` are designated for retirement, but their
network/fleet access and associated credentials have not yet been revoked.

impact: retaining obsolete trusted identities leaves unnecessary access after
the decision to retire their computers.

evidence: both appeared as offline tailscale devices during the 2026-10-23
inspection; the owner subsequently directed retirement of both. that decision
replaces the earlier inspect-or-retire choice. live retirement is NOT_RUN.

resolve each device separately: match its exact enrolled identity; remove
tailscale membership, any remaining fleet enrollment and owned configuration
references; review and revoke associated device-specific credentials. record
shared-credential rotation separately without disrupting active consumers.
preserve disks and data. host reachability is not required for account-side
revocation; access to the owning accounts is required.

resolved when each device has its own verified, non-secret access-removal result
and credential review under the [security plan](../fleet-security-spec.md).
`dev-server` owns this work and its records.
