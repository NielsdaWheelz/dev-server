# native notification deployment qualification

problem: the new managed mac/devbox deployment and complete prior-release
rollback have not been exercised on the installed fleet. release pins are
unchanged. the first temporary stage diverted the normal api; its routes were
restored and its services removed. qualification used six owned user
services and five handlers on three separate qa tailnet addresses, with a
distinct android app. those services, isolated tmux servers, stage directories
and qa applications are now removed; production routes/pairings and phone
packages stay unchanged. phone distributor cleanup is complete; authenticated
admin search confirms all three retired qa node names are already absent.
no other devices changed.
permanent deployment and release pins have not changed. mac candidate admission
requires the new signed bundle; publish and pin its matching release before
applying the notification cutover. there is no old-archive fallback.

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
clean committed-source release provenance remains `NOT_RUN`.

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

impact: these establish packaging/installer control flow, pinned server
configuration and temporary managed routing. complete installed release and
rollback remain unqualified.

resolution: qualify the exact signed release with source/member/signer/version
checks; managed login/restart and devbox services; authenticated private paths
without foreign ingress changes; partial notification failure followed by same
input repair; saved fleet-client restoration and prior runtime/unit/root-cli
restore; actual android platform rollback. provider history and tmux workers
must survive. remove temporary tests after recorded acceptance.

blockers: actual deployment/publication belongs to the root cutover operator;
phone rollback and native consent require the app owner's physical qualification.
these boundaries are `NOT_RUN`, never passes.
