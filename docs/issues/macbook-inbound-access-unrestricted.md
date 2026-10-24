# macbook ingress lacks an explicit private boundary

problem: the application firewall is disabled and launchd's ssh sockets listen
on all interfaces. other apple services also have non-loopback listeners.

impact: local-network access is not restricted to approved tailscale devices by
the application firewall. public-internet reachability has not been established;
privileged runtime pf rules were not inspected.

evidence: 2026-10-23 `socketfilterfw --getglobalstate` returned disabled;
`netstat -anv -p tcp` showed wildcard tcp `22`, `5000` and `7000` listeners.
the installed apple ssh launchd plist owns socket creation, so sshd listener
configuration alone is insufficient proof.

prerequisite checks confirmed fresh arch-to-mac lan connections over ipv4 and
global ipv6 to ssh and active docker lab publications. those unrelated labs
remain running. the user is a local administrator, but agent-side sudo is
unauthorized; privileged runtime pf/effective ssh inspection needs one locally
authenticated read-only check before choosing the final packet rules.

resolved when the [security plan](../fleet-security-spec.md) host boundary blocks
fresh unapproved lan/ipv6 ingress, permits approved tailscale ssh/skid, preserves
required local workflows, and survives reconnect, sleep and reboot. implementation
and live acceptance are NOT_RUN; local administrative access is needed to apply
and inspect privileged firewall policy.
