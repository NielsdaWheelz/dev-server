# macbook tailscale self-ipv6 https times out

problem: macbook times out when connecting to its own tailscale serve `8443`
endpoint while forcing its `fd7a:115c:a1e0::3138:af0b` destination and retaining
the normal hostname and certificate validation.

evidence: on 2026-10-24 utc, the activated self-access repair `e32b35d` restored
ipv4 self-https and all nine ordinary hostname mesh paths passed. remote peers
also reached macbook over ipv6. the forced self-ipv6 probe still timed out and
the privileged verification helper correctly returned nonzero for that gap.
hostname success does not establish which address family worked.

cause is unestablished. the active urpf quick-drop rule matched zero packets in
the recorded probe window; loopback-pass and default-deny counters increased.
these aggregate counters do not identify where the failed connection was lost.
the kernel routes self-ipv6 through loopback; tailscale's interface-bound local
listener is another possible factor, not a proven upstream bug. no firewall or
grant relaxation is justified by these observations.

impact: literal self-ipv6 gateway access remains broken despite ordinary mesh
success. keep the qualified-family check failing until its positive path works.

resolved when certificate-valid self-https forced to that ipv6 destination
returns the normal gateway response, while remote ipv6 still works and fresh
physical-lan denial passes in both address families. do not lower the gate.
