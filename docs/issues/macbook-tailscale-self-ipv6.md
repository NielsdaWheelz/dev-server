# macbook tailscale self-ipv6 https times out

problem: macbook times out when connecting to its own tailscale serve `8443`
endpoint while forcing its `fd7a:115c:a1e0::3138:af0b` destination and retaining
the normal hostname and certificate validation.

evidence: on 2026-10-24 utc, the activated self-access repair `e32b35d` restored
ipv4 self-https and all nine ordinary hostname mesh paths passed. remote peers
also reached macbook over ipv6. the forced self-ipv6 probe still timed out and
the privileged verification helper correctly returned nonzero for that gap.
hostname success does not establish which address family worked.

cause is unestablished. pre-upgrade aggregate pf counters did not identify where
the connection was lost. after the macos `27.0.1` reboot on 2026-10-25, self-ipv6
still timed out while the live root contained only apple anchors: the owned
anchor was unreferenced. these observations do not establish the owned rules as
the cause. earlier inspection found a loopback self-route; tailscale's
interface-bound local listener remains a possible interaction, not a proven
upstream bug. no firewall or grant relaxation is justified.

impact: literal self-ipv6 gateway access remains broken despite ordinary mesh
success. keep the qualified-family check failing until its positive path works.

resolved when certificate-valid self-https forced to that ipv6 destination
returns the normal gateway response, while remote ipv6 still works and fresh
physical-lan denial passes in both address families. do not lower the gate.
