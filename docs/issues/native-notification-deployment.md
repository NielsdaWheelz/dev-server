# native notification deployment qualification

problem: v0.14.0 is deployed, but complete prior-release rollback and current
physical notification acceptance remain unqualified.

2026-10-09 deployment: the owner authorized the signed release and all-machine/
android rollout. the pin now selects immutable v0.14.0, exact source
`111c91b4c97e70ee154dae3032d011533951f55e`. published-release validation passes
for source, all five assets, signer/version identities and upstream pin.
managed apply and upstream fleet verification pass on macbook, devbox and arch.
devbox's gateway, observer and ntfy services are healthy; private gateway and
notification/ntfy handlers are installed. the signed mac app and producer are
healthy. root's jarvis cli uses the same admitted linux release; jarvis remains
inactive. the attached android app updates in place to `0.14.0` / `14000`, with
unchanged first-install time. phone notification enrollment still requires a
fresh v2 fleet qr and production ntfy setup.

the first devbox observer activation rejected the old client config. supported
fleet provisioning saved each exact prior config and added notification inputs;
same-release reapply restored health. machine identities, bearer/peer credentials
and ownership remain unchanged. devbox's three original session/provider identities
are unchanged; concurrent owner activity makes macbook inventory unsuitable as a
preservation witness. no production session was deliberately restarted or closed.

gateway-only apply also exposed an omitted provider dependency: the installed
skid `claude-work` version probe failed on devbox/arch because
`~/.local/share/dev-server/memory-profile.sh` was absent. the repair includes
`assets/memory/profile-env.sh` in both declared snapshots/stages and ansible copy,
then installs it through the shared ai owner before provider activation. managed
reapply passes on all three hosts without service activation; exact helper bytes,
mode/ownership and installed launcher version probes pass. full host/package
apply is not required for this dependency. bash syntax, focused shellcheck
(excluding pre-existing workstation `SC2119`) and gateway ansible syntax pass.

earlier temporary qualification: the first stage diverted the normal api; its
routes were restored and its services removed. qualification used six owned user
services and five handlers on three separate qa tailnet addresses, with a
distinct android app. those services, isolated tmux servers, stage directories
and qa applications are now removed; production routes/pairings and phone
packages stay unchanged. phone distributor cleanup is complete; authenticated
admin search confirms all three retired qa node names are already absent.
no other devices changed during that cleanup. mac candidate admission requires
the new signed bundle; there is no old-archive fallback.

evidence: temporary tests used a real baseline darwin archive (missing-app red),
the actual pinned ntfy `2.28.0` official binary in isolated owned containers
(private renderer, declarative startup, retained credentials green), controlled
serve commands (all three routes preserve foreign handlers green), and real unit
files/receipts (prior-unit deletion red, paired retention green; interrupted
rollback retains its target and retry consumes the checkpoint). service stand-ins
verify inactive mac jobs restart, healthy jobs stay, and a fleet-client-only change
reloads the observer once. a real authenticated loopback request with tracing
enabled keeps its headers private. native bash, shellcheck with source following,
and ansible syntax checks pass.

signed working-tree qa archive: exact darwin bundle tree/modes, native signature
and leaf pin, release identities, public icon/plist/entitlement reproduction,
and native executable reproduction pass. fresh/cache native admission passes;
flat candidates/caches and modified signed resources reject. apple's native
signing tool normalizes signing allocation on private audit copies before
signature removal/comparison; executable instruction changes remain detectable.
clean committed-source release provenance now passes for published v0.14.0.

real mac installation exposed a launch services rejection of application
symlinks (`-10811`). the corrected installer copies and validates a real bundle,
stops before replacement and invokes its exact-path public registration mode
before activation. controlled failure tests pass. on 2026-10-04, actual signed
0.13.3 and 0.13.4 native installations through stock admission/apply passed in a
private root under user Applications: exact bundle bytes/default registration,
offline-to-healthy client restart, unchanged apply and two-build enabled
alert/sound permission continuity. stock removal removed only its own job,
app/unit/fingerprint and retained private state. the temporary unit preserved
real HOME and explicitly fixed private XDG state. normal-home activation,
global launch-services registry restoration and history across upgrade remain
unqualified. the stock unit now fixes its managed state path: actual inherited
XDG moved the helper socket away from installer checks (native red), and the
same signed helper/socket passed after the explicit unit setting (green).
both exact children stopped and their copied apps were removed; no global gui
environment was changed. the app owner qualified mac native delivery,
exact-session click, two-build consent and earlier physical-phone rollback.

impact: published packaging, managed fleet installation and service health are
qualified. installation does not establish physical delivery/click or complete
rollback behavior.

resolution: qualify the exact signed release with source/member/signer/version
checks; managed login/restart and devbox services; authenticated private paths
without foreign ingress changes; partial notification failure followed by same
input repair; saved fleet-client restoration and prior runtime/unit/root-cli
restore; actual android platform rollback. provider history and tmux workers
must survive. remove temporary tests after recorded acceptance.

blockers: full phone rollback and native consent/delivery require the app owner's
physical qualification. complete coordinated rollback remains `NOT_RUN`, never
a pass.
