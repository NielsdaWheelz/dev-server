# macbook post-transition physical-lan verification remains

remaining scope: repeat controlled physical-lan denial when a peer is on the
same network. boot and sleep/wake retained the firewall policy and approved
private access. no further owner sleep/reboot steps are required for this check.

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

new evidence, 2026-10-27: native logs show sleep at 08:45:32 and full wake at
08:57:25, america/los_angeles time. the owner's read-only report followed at
08:59 without an intervening reboot; boot identity remains `1793029475`.
persistent/live root hooks, full owned rules, enabled pf, application firewall
and key-only ssh pass. installed loader bytes still match reviewed source.
fresh arch pinned ssh and certificate-valid https pass in actual ipv4/ipv6.
no policy was reapplied before inspection.

macbook and arch remain on different physical networks, so the earlier
physical-lan denial proof cannot be repeated from arch today. this missing
effect check is not an observed exposure. the known forced self-ipv6 failure
remains a separate functional issue; the helper still exits nonzero for it.

resolved when controlled physical-lan ssh/media probes fail in both families
with matching local-listener and peer-route controls, while approved private
ssh/https still works in both families. retain local recovery access. arch's
corresponding transitions already passed.
