# macbook sleep and reboot verification is deferred

remaining scope: the owner explicitly deferred sleep/wake and reboot
verification after the repaired boundary and controlled tailscale reconnect
passed. these transitions have not been qualified with the installed repair.

evidence from 2026-10-25 utc: the installed loader matches reviewed `c670e208`.
persistent/live root hooks, full owned rules/table, enabled pf, application
firewall and key-only ssh pass. repeat native activation is inert. fresh arch
ssh/https passes in true ipv4/ipv6; physical-lan ssh/media denial passes with
matching local listeners and valid peer routes/neighbors.

the controlled tailscale down/up retained preferences, node identity, addresses
and serve configuration; fresh peer allow/deny checks passed afterward. the
earlier os-reset root-hook failure is repaired and activated.

impact: these results establish current enforcement and reconnect behavior, but
not the two deferred transitions. the deferral is not an observed exposure.

resolved when the owner chooses a suitable window and sleep/wake plus reboot
retain the root hook, owned policy, fresh approved ssh/https access and
physical-lan denial in both families. retain local recovery access. arch's
corresponding transitions already passed; self-ipv6 remains a separate functional
issue.
