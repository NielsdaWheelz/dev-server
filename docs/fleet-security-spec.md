# fleet security specification and implementation plan

date: 2026-10-23. status: fleet boundaries applied and core checks passed,
including macbook's repaired root hook and tailscale reconnect. sleep/reboot
verification is deferred by the owner; self-ipv6 and account checks remain
tracked below. this document is the cross-repository plan. each repository
retains ownership of its own deployment and runtime contracts.

owner decisions: retire `skq-linux` and `niels-desktop`; keep macbook, arch,
devbox, retirement and the shared tailnet policy in `dev-server`; keep both the
nexus vps and public website changes in `nexus-web`. both retired computers'
network memberships are removed; the owner confirms both disks remain securely
retained, active ssh fingerprints are accounted for, and the unknown github key
has been revoked.
the api moves to `nexus-api.nielseriknandal.com` under the existing free
certificate; the public website address stays unchanged. no subscription is added.
nexus retains its own [deployment contract](../../nexus-web/deployment.md).

## current activation status

updated 2026-10-25 utc after macbook's repair activation and controlled reconnect.
these are live activation results, distinct from the historical baseline below.

| target | established | still pending |
|---|---|---|
| tailnet and retired computers | reviewed three-grant policy and fourteen policy tests active; prior nine-path hostname mesh and production containment qualification passed; retired devices absent from tailscale/skid, disks securely retained by owner; active ssh keys accounted for and unknown github key revoked; phone opened terminals on all three computers | none within the current secure-retention decision; review offline shared credentials before transfer/disposal |
| macbook | macos `27.0.1` build `26A434`; installed loader matches `c670e208`; persistent/live root hook, full owned rules/table and enabled pf verified; application firewall and key-only ssh remain correct; fresh arch ssh/https and physical-lan denial pass in true ipv4/ipv6; repeat loader inert; controlled tailscale reconnect preserved identity/preferences/serve and passed fresh peer checks | sleep/reboot verification deferred by owner; forced self-ipv6 remains a separate functional issue |
| arch | 194 repository updates and declared aur packages applied; rebooted into `7.2.11`; S3 sleep/resume passed with unchanged boot identity; private ssh/8443 and lan denial passed in both address families afterward; docker controls/forwarding passed; no failed units or remaining repository updates | none |
| devbox | native apt maintenance and runtime/pam refresh completed; kernel `6.8.0-147` matches installed; no failed units or needrestart service/session entries; skid and the same two rootless builders recovered with true ipv4/ipv6 https; rootful docker/containerd remain inactive; observed 26.5 gib free | none |
| nexus | current independent deployment `c5cf4bc27a1f9838b630b177209e15c5bba87c99`, wire `15`, all eight services healthy; private perimeter passes in both families; security-cutover/recovery and extended asset/stream qualification complete; signed firefox `1.0.1` independently qualified with release ownership recorded in nexus | none for this scope |

public api tls is verified, version responses are uncached, and the existing
website dns record is unchanged. the tunnel has one connector and four edge
connections; these are transport evidence, not proof of every client journey.
the owner confirmed desktop document/ai use and extension account/destinations.
the agent verified android account/text reading. nexus's extended upload, range,
reading-copy and long-stream checks also passed, with owned fixtures cleaned.

offline shared credentials were neither inspected nor rotated; secure retention
is the owner's accepted present custody, with review required before either
retired disk is transferred or disposed of.

the increased devbox headroom was observed without cleanup by this work; its
cause is unestablished. account mfa/recovery retains an issue record. no blanket
fleet or release acceptance is claimed.

## purpose and limits

keep nexus publicly usable while removing direct internet access to its server.
restrict fleet administration to approved tailscale devices. contain production
so enrolling it does not grant access to personal computers or development
services. protect workstations on untrusted local networks as well as the
internet.

network controls decide which services a caller can reach. application
authentication decides what that caller may do. patching and existing process
isolation remain responsible for vulnerabilities in reachable software. a tunnel
does not make public application requests safe.

preserve browser, android, extension, anonymous sharing, current sign-in, skid
pairings and terminal access, ssh keys and host-key trust, editor forwarding,
provider accounts and active work. visitors need neither tailscale nor an added
cloudflare login. preserve existing application and codex isolation; no provider
permission changes, operating-system replacement, new gateway product, general
security framework, or high-availability infrastructure belongs to this work.

## observed baseline

observations are from the read-only investigation on 2026-10-23. recheck before
each cutover; they are not desired-state declarations.

| target | verified observation |
|---|---|
| devbox, `dev-server` | hetzner context `dev-infra`; one attached firewall permits only udp `41641`; ufw denies public ingress and accepts tailscale; ordinary openssh, tailscale ssh disabled; fresh public tcp probes to `22/80/443/8443` failed over ipv4 and ipv6 |
| nexus, `nexus-api-worker` | hetzner context `dev-server`; public tcp `80/443`; ssh restricted to two public source addresses; api dns resolves directly to the vps; direct-origin `/version` succeeds; tailscale and cloudflared absent |
| macbook | application firewall disabled; launchd listens on wildcard ssh sockets; apple services also listen on non-loopback addresses; internet reachability and privileged runtime pf state unverified |
| arch | firewalld running; wlan public zone permits only dhcpv6-client; ssh permitted in tailscale zone; global ipv6 addresses exist; no running docker containers |
| tailscale | effective filters on macbook, arch and devbox allow all ports from tailnet addresses; all three use private serve tcp `8443` to loopback skid `7341`; no funnel appeared in those serve snapshots |
| other devices | android phone online; `skq-linux` and `niels-desktop` offline and not inspected |
| maintenance | nexus reports reboot required and cached package updates; unattended security updates enabled; devbox also has package updates; cached listings are not a vulnerability assessment |

the nexus database and api container ports are not published directly. caddy
publishes tcp `80/443` and udp `443`; provider policy currently blocks that udp
publication. devbox has an old public caddy listener, but both verified perimeter
layers block its public web ports.

## target boundaries

```text
public browser / android / extension
  -> nexus.nielseriknandal.com:443 on vercel
  -> nexus-api.nielseriknandal.com:443 on cloudflare
  -> existing outbound cloudflared tunnel
  -> private caddy -> api -> existing private database and workers

approved operator computer -> tailscale -> ordinary openssh on managed hosts
approved fleet clients -> tailscale serve:8443 -> loopback skid:7341
```

the email worker and existing public api health probes use the cloudflare api
hostname too. direct r2 upload/download capabilities keep their existing routes.
vercel, supabase and r2 remain separate public services with their existing
authentication. this is not a claim that all nexus traffic traverses the vps waf.

required invariants:

1. no managed server accepts direct public ssh, web, database, debug, metrics,
   provider-daemon or development-service connections, in either address family.
2. public nexus traffic reaches the vps only through its named cloudflare tunnel.
   existing application authentication and public route semantics remain intact.
3. public udp `41641` is the deliberate exception on the two vps firewalls, for
   tailscale's authenticated encrypted transport. ordinary outbound connections,
   their replies, and required network-control traffic remain available.
4. production may receive approved administration but initiate no tailnet
   application connections. established replies are allowed. it receives no skid
   enrollment or development credentials.
5. every permitted tailnet connection has named source devices, destinations and
   ports. remove the effective allow-all rule; adding narrower rules beside it
   does not restrict access. new or unidentified devices receive no permissions.
6. loopback developer services and existing authorized ssh forwarding remain
   usable. network gates persist through reboot and tailscale reconnect.
7. cloudflare, tailscale, dns, or tunnel failure never automatically reopens a
   public origin. local/console recovery remains available.

## tailnet policy

use one reviewed tailscale grants policy, with built-in allow/deny policy tests.
select exact enrolled devices; ensure selectors cover their overlay ipv4 and
ipv6 identities. give production the dedicated `tag:nexus-prod`, whose ownership
is restricted to the account administrator. avoid a broad user selector that
would also authorize old or newly enrolled devices.

| initiating devices | destination | permitted service |
|---|---|---|
| macbook, arch | devbox, nexus production | tcp `22`, ordinary openssh |
| macbook, arch | the other operator workstation | tcp `22`, ordinary openssh |
| macbook, arch, devbox | macbook, arch, devbox | tcp `8443`, direct skid peer access |
| enrolled android phone | macbook, arch, devbox | tcp `8443`, direct skid client access |
| production | any other tailnet device | none |
| retired `skq-linux`, `niels-desktop` | any device | none; revoke membership and associated access |
| other unidentified devices | any device | none until explicitly admitted |

this is the minimum intended matrix, not executable policy. preflight must
compare it with actual editor, terminal and automation routes. report any
required deviation before changing the matrix; do not silently add wildcard
access. workstation-to-workstation ssh is operator access, never a grant for
devbox to initiate workstation ssh.

skid uses a direct mesh, including phone-to-peer requests and terminal
websockets. a hub-only rule would break it. permitting those ports retains
skid's existing authority to operate remote terminals: devbox remains trusted
within that fleet. production is outside that trust group.

inventory the separately owned memory service before denying other tailnet
ports: [the host contract](../SPEC.md) reserves devbox https `443 /v1` for
memory, although no such serve mapping was observed. preserve a verified active
consumer through a specific source-to-devbox rule, or record it inactive; do
not activate it as part of hardening. icmp diagnostics, if needed, get explicit
device-scoped permissions rather than an all-protocol grant.

verify policy membership, tag ownership, sharing, subnet routes, exit-node
permissions and funnel capabilities. remove only identified obsolete exposure;
preserve unrelated dns and service attributes. review tailscale identity-provider
mfa and recovery without replacing account ownership or logging credentials.

retire the two named computers without waiting for them to come online. first
match their exact device identities; revoke tailscale membership and any
remaining fleet enrollment, remove their owned access/configuration references,
and review credentials previously entrusted to them. revoke device-specific
credentials; record required shared-credential rotation separately and preserve
active consumers during that rotation. retain their disks and data. capture a
separate non-secret retirement result for each device. exclusion from the new
grants policy alone is not proof of complete access retirement.

## host enforcement and ownership

| owner | implementation responsibility |
|---|---|
| `dev-server/devbox`, ansible security role and cloud-init template | retain devbox's private hetzner/ufw boundary and key-only openssh; future apply/bootstrap must preserve it |
| `dev-server/lib/personal-macos.sh` and owned assets | application firewall, explicit packet boundary, ssh policy and persistent activation on macbook |
| `dev-server/lib/personal-arch.sh` and owned assets | public/tailscale firewalld zones, ssh policy, explicit ingress verification and docker publication audit on arch |
| `dev-server`, applied through the tailscale account | the single grants policy, exact device membership and retirement records; keep reviewed desired policy and non-secret provider-side changes here |
| `nexus-web/deploy/hetzner/` | production host tailscale, firewall declarations, ssh coordinate, compose, caddy, health/resource proofs, bootstrap and release runbook |
| `nexus-web/deploy/vercel/` and existing web configuration owners | public frontend/bff routing and configuration; preserve current public client access |
| `nexus-web/deploy/cloudflare/`, applied through the cloudflare account | named tunnel, exact api hostname route, edge certificate, waf/cache settings and non-secret provider-side change records |
| existing native package owners | supported updates, restart requirements and maintenance evidence |

put repeatable configuration in its owning repository. when a provider setting
must be applied outside a repository, record its desired state and the applied
change with that repository's release work. `dev-server` owns the fleet-wide
tailnet policy; nexus declares its required identity and connections and links
to that policy, without maintaining a duplicate. nexus-specific issues and
release steps live in `nexus-web/docs/issues/`.

reuse existing configuration installers and native service managers. ordinary
`./workstation apply` and `./devbox apply` must retain their existing package and
activation contracts; no new all-host runner or generic orchestration layer.
account policy changes remain explicit provider operations, not hidden side
effects of host apply.

macbook needs both application and network enforcement. retain apple's existing
pf anchors and unrelated rules; add one owned anchor and the smallest native
persistent activation needed. the native root loader owns the persistent hook,
repairs it after an os reset, and verifies its live root-anchor postcondition;
workstation apply installs and invokes that same owner. retain the strict
empty/apple-only live-root guard before a required root reload. do not flush the
root ruleset, edit the sealed
apple ssh plist, or hard-code today's `utun` number. fail closed if the approved
tailscale path is unavailable. the implementation must prove how its rules
identify that path after interface changes. application firewall enablement or
`sshd_config` `ListenAddress` alone is insufficient: launchd owns the ssh sockets.
deny unapproved incoming connections on physical interfaces while preserving
loopback, established replies, required networking and approved tailscale traffic.
inventory apple discovery/sharing features; retain local-network exceptions only
when their purpose and scope are explicit.

on linux, verify actual input/forwarding rules and docker bindings, not merely
ufw/firewalld status. ordinary developer listeners should bind loopback; no
unapproved wildcard docker publications may bypass workstation ingress policy.
keep required ipv6 control traffic; dropping all icmpv6 breaks networking.

ordinary openssh keeps key-only authentication, no root login, named users,
existing host keys and existing required local forwarding. preserve
`GatewayPorts no` and agent-forwarding defaults. verify effective configuration
and new authenticated connections before disabling any old authentication path.
do not turn on tailscale ssh as an incidental migration.

## nexus public ingress

use one production named tunnel and one `cloudflared` compose service. route only
`nexus-api.nielseriknandal.com` to private caddy; unmatched hostnames fail closed.
keep the website hostname and application contracts.

- the account's active wildcard covers the chosen first-level api hostname.
  update backend/frontend configuration and any configured email-worker target
  together. verify a fresh edge handshake before closing public origin access;
  retire the old api dns record after the new route passes. no tls bypass or
  certificate subscription is used.
- remove all caddy host port publications, including udp `443`; expose neither
  cloudflared metrics nor its management endpoints on the host.
- private caddy uses http on the existing compose network. cloudflare owns the
  public certificate; the connector encrypts the external tunnel. retain caddy's
  security headers and redacted logs. `CADDY_SITE` remains the bare hostname;
  changing it to an http url would break release health checks.
- pin cloudflared by immutable image digest. run as its verified non-root uid,
  with dropped capabilities, no docker socket, no privileged mode and no
  database, provider-state or application-secret mounts. use the existing compose
  network; do not attach it to the isolated codex private network.
- use a narrowly scoped tunnel token through `--token-file`, mounted read-only.
  keep its source in a root-only host directory, root-owned and readable only
  by the selected container gid (`0440`); verify image uid/gid and host group
  ownership before installation. bind-mount the file itself, not its root-only
  parent directory; verify readability as the container uid. no token in
  arguments, image metadata, committed
  env inputs, process output or logs. existing secret publication owns delivery;
  tunnel-credential rotation is explicit and verified.
- allow outbound tunnel connectivity and normal existing application egress.
  no blanket outbound filtering or cloudflare source-ip allowlist is needed for
  the tunnel design.
- bypass cloudflare caching for the entire api hostname, preserving `no-store`,
  cookies, bearer/internal headers, range requests and content types. api traffic
  must not encounter interactive browser challenges. enable the available free
  managed waf rules and verify them; use only narrow evidenced exceptions.
- qualify sse delivery/reconnect, long reading-copy requests, private assets,
  signed downloads, uploads and email ingest. review actual plan limits and media
  terms against those paths; do not assume unlimited proxied uploads or streaming.
  document bytes uploaded directly to r2 remain outside the api waf.

add cloudflared to the release service inventory, stock-image identity checks,
health checks and resource assertions. use its native readiness command against
a fixed loopback metrics listener; prove public requests separately. a healthy
connector alone does not prove the application route works.

pull and verify the pinned connector image alongside application images before
stopping writers, then enforce the existing post-pull disk floor. a first-time
connector registry/download failure must not be deferred until compose startup
inside the outage.

add explicit memory/pid limits and the existing no-swap slice membership.
measure a representative concurrent workload on the 2 gib vps; preserve the
current preflight memory/disk floors and existing service limits. select the
connector cap from measured behavior, with recorded headroom. insufficient
capacity blocks deployment until a concrete capacity decision; do not lower a
gate to obtain a pass.

install tailscaled as a host service independent of docker and the encrypted
codex volume. use a stable reviewed production ssh alias resolving through
tailscale, pinned to the existing host key. update release/config/backup/unlock
runbooks and tools that use the public ip, including `release.py` and
`sync-env.sh`. preserve the existing linear release owner and its exact-source
checks. update provisioning too, so a rebuild cannot recreate public ingress.

## implementation sequence and recovery

1. **prepare.** recheck named hosts, all attached firewalls, dns records, listener
   bindings, actual tailnet routes and approved consumers. verify account access,
   mfa/recovery, exact api edge-certificate coverage, current verified nexus
   backup, a usable independent console login and the encrypted-state unlock
   source before any reboot or administration closure. console transport alone
   is insufficient. capture
   only necessary non-secret configuration and securely retain rollback material.
   identify outstanding desktop/reboot work before choosing the no-use window.
2. **implement and review source.** make isolated changes in the owning repos;
   review the policy matrix and boundary implementation independently. add focused
   regression checks where a wrong rule could expose a service or lock out the
   operator. publish reviewed source before its normal live activation.
   base the nexus security release on the deployed wire-14 source, merge its
   reviewed commit into main with a true merge commit, and build exact-source
   backend and staged production-target frontend artifacts. this preserves the
   current clients without relaxing release ancestry or bundling main's unrelated
   wire-15 product cutover.
3. **restrict the existing tailnet.** validate built-in policy tests, then replace
   the allow-all policy. prove fresh operator ssh and the full skid mesh before
   joining production. retire the two named computers through the account and
   any remaining fleet enrollment, and review their credentials without waiting
   for host reachability. retain account-console access for policy recovery.
4. **protect workstations.** apply macbook policy from its local console first;
   prove fresh lan denial and tailscale success. reconcile arch, then devbox.
   inspect each host before advancing. do not interrupt unrelated tmux or agents.
5. **establish production administration.** enroll host tailscale with the
   restricted production identity. deploy the reviewed ssh coordinate and prove
   fresh key-authenticated administration and maintenance from both operator
   computers. remove public ssh rules after those checks; keep console recovery.
6. **cut over the api.** prepare the named tunnel route, edge certificate,
   credentials and reviewed release candidate. reduce the dns ttl sufficiently
   ahead of time for its previous ttl to expire. at the start of the planned
   no-use window, switch api dns to the tunnel and confirm the release
   controller's resolver sees cloudflare. then invoke the normal exact-source
   release, which starts private caddy/cloudflared and proves public health
   before promoting vercel. the tunnel can be unavailable between the dns switch
   and service startup; this is a planned outage. do not wait for the release
   command to finish before switching dns: its mandatory public health check
   would fail against the closed old origin. repair and rerun the same source
   after a failed check; add no second release state machine. after public
   behavior passes, remove public web allowances.
   check every attached firewall; their allow rules combine. transient cached
   old dns may fail after closure; this is preferable to retaining an origin
   bypass. measure and record the actual interruption.
7. **maintain and prove persistence.** apply reviewed native updates in scheduled
   windows, respecting package scripts that may restart services. reboot nexus
   deliberately, unlock its encrypted codex volume through the existing runbook,
   and verify docker, generation, workers, backup readiness and public service.
   test workstation reconnect/sleep and required reboots. do not call an installed
   update active while its old process/kernel remains loaded.
8. **close the fleet.** verify separate retirement results for `skq-linux` and
   `niels-desktop`, including removal of access and any credential follow-ups.
   verify the phone's client behavior and software/security-update state. keep
   unresolved provider/account steps visible as issues, never blanket completion.

retain a separate known-working connection and console route during each
administrative cutover. an existing ssh connection surviving proves nothing
about new connections. if policy fails, restore the previous exact account/host
policy through its independent recovery path, identify the failed rule and
retry. never broaden access to the whole internet as an automatic fallback.

for ingress recovery, repair the tunnel and rerun the same source, or release a
new reviewed repair/revert commit with its own matching artifacts through the
existing release owner. arbitrary old-source rollback is not guaranteed by the
forward-only migration contract. any emergency return to direct public ingress
is a deliberate, recorded exception, not normal rollback. no automatic database
downgrade, whole-host restore, provider credential copy or firewall flush. native
package updates keep their native repair semantics.

## acceptance and completion

retain dated source revisions, device identities, policy version, connector
digest, non-secret provider receipts, probe vantage points and pass/fail results.
local/static proof, hosted ci and installed/live acceptance are distinct.

| boundary | required evidence |
|---|---|
| source and bootstrap | focused policy/rendering checks; native syntax/config validation; future host apply and nexus provisioning preserve the same closed ingress; repeat apply is inert for unchanged owned policy |
| operator access | fresh key-authenticated ssh from macbook and arch to each permitted destination; host-key verification preserved; existing editor/forwarding journey works |
| tailnet containment | built-in policy allow/deny tests plus live denied production-to-workstation/devbox probes; use `22/8443` targets first proved listening and reachable from an allowed source in the same overlay family; production public egress still works |
| skid | each computer reaches each peer; phone lists all peers and opens an existing terminal on each; pairing and active work survive; no funnel |
| workstation physical network | fresh probes from another device on the same lan fail for ssh, skid backend, developer/debug and observed sharing listeners; permitted tailscale connections still work; external ipv6 checked where routed |
| public vps perimeter | fresh external probes to `22/80/443/8443` and all observed app/admin/database listeners fail on both public address families; all firewall attachments checked; udp transport exception documented |
| public nexus | dns uses the named tunnel; direct-origin HTTPS with the correct host/SNI fails; version is exact-source and uncached; signed-in browser/android/extension plus anonymous share work without extra login |
| application traffic | sse/reconnect, private/range assets, reading-copy, direct r2 upload/download and configured email ingest work through their intended paths; no challenge html or cache leak |
| capacity and credentials | connector limits hold under representative concurrency; existing readiness floors and codex isolation remain true; token is absent from committed files, arguments and logs |
| persistence and recovery | tailscale reconnect and workstation sleep/reboot retain denial; nexus reboot reaches host ssh before volume unlock and restores full service after unlock; console and backup recovery prerequisites verified |
| maintenance and coverage | supported update status and pending restart outcomes recorded per active device; both named retired computers have separate verified access-removal results and credential review; account mfa/recovery steps recorded without secrets |

a single fresh external vantage plus matching provider/host rules is sufficient
for ordinary port-denial evidence. use a second vantage only to resolve an
ambiguous network failure. negative socket tests prove denial, not its exact
enforcing layer. a closed port or broken ipv6 route cannot prove a policy denies
a working service. neither failed ping nor a listening socket alone proves
public reachability.

mark a row NOT_RUN when its real boundary was not exercised. once the focused
checks pass, add tests only for a concrete remaining concern. retain compact
evidence rather than a new permanent verification service. remove only task-owned
temporary resources. update or delete resolved issue records.

## tracked outstanding work

- [workstation security persistence](issues/workstation-security-persistence.md)
- [macbook tailscale self-ipv6](issues/macbook-tailscale-self-ipv6.md)
- [fleet account recovery](issues/fleet-account-recovery-review.md)

new failures get one issue each, with problem, impact, evidence and resolution
proof. all rows above must pass before calling this scope complete; an explicit
exception remains an exception, with its owner and consequence recorded.

## source references

- [tailscale grants](https://tailscale.com/docs/features/access-control/grants)
  and [firewall transport](https://tailscale.com/docs/reference/faq/firewall-ports).
- [apple application firewall](https://support.apple.com/guide/mac-help/block-connections-to-your-mac-with-a-firewall-mh34041/mac);
  local `ssh.plist`, `pf.conf` and installed native manuals govern the mac packet
  boundary; validate against the installed os version.
- [hetzner firewall semantics](https://docs.hetzner.com/cloud/firewalls/faq/)
  and [docker firewall behavior](https://docs.docker.com/engine/network/packet-filtering-firewalls/).
- [cloudflare tunnel firewall requirements](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-with-firewall/),
  [token files](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/),
  [native readiness implementation](https://github.com/cloudflare/cloudflared/blob/master/cmd/cloudflared/tunnel/subcommands.go),
  [edge certificate coverage](https://developers.cloudflare.com/ssl/edge-certificates/universal-ssl/limitations/),
  and [waf availability](https://developers.cloudflare.com/waf/).
- sibling repository owners: `nexus-web/deployment.md`,
  `deploy/hetzner/{release.py,provision.sh,cloud-init.yml,docker-compose.yml,Caddyfile,sync-env.sh}`,
  `docs/runbooks/codex-personal-agent-host.md`; skid direct routing:
  `skidbladnir/internal/fleetclient/{config.go,client.go}` and android
  `GatewayClient.kt`.
