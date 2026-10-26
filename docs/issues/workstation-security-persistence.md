# macbook post-wake boundary verification remains

remaining scope: inspect the boundary after sleep/wake before another reboot,
and repeat controlled physical-lan denial when a peer is on the same network.
boot persistence and approved private access passed on 2026-10-26.

evidence from 2026-10-25 utc: the installed loader matches reviewed `c670e208`.
persistent/live root hooks, full owned rules/table, enabled pf, application
firewall and key-only ssh pass. repeat native activation is inert. fresh arch
ssh/https passes in true ipv4/ipv6; physical-lan ssh/media denial passes with
matching local listeners and valid peer routes/neighbors.

the controlled tailscale down/up retained preferences, node identity, addresses
and serve configuration; fresh peer allow/deny checks passed afterward. the
earlier os-reset root-hook failure is repaired and activated.

new evidence, 2026-10-26: native logs show sleep at 08:22:40, wake at 08:38:57,
then a new boot at 08:44:35, all america/los_angeles time. the owner's read-only
report was collected after that boot. the reviewed loader was installed before
boot; its boot job ran once and exited zero. persistent/live root hooks, full
owned rules, enabled pf, application firewall and key-only ssh pass. fresh arch
ssh and certificate-valid https pass over actual ipv4 and ipv6. no policy was
reapplied before inspection.

the intervening reboot prevents this report from proving the earlier post-wake
state separately. macbook and arch are now on different physical networks, so
the earlier physical-lan denial proof cannot be repeated from arch today.
neither limitation is an observed exposure. the known forced self-ipv6 failure
remains a separate functional issue; the helper still exits nonzero for it.

resolved when a read-only report collected after wake, before another reboot,
retains the root hook and owned policy, fresh approved ssh/https works in both
families, and controlled physical-lan probes still fail in both families when a
same-lan peer is available. retain local recovery access. another reboot is not
required to establish the already verified boot result. arch's corresponding
transitions already passed.
