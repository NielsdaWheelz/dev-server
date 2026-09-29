# native provider installation qualification

helper source is pinned directly to merged `0bbba0a`; its updated anyio lock
and new generation have not passed live qualification. `qualified: false`
blocks gateway application. the final approved disposable frozen install and
repeat application passed, including exact runtime versions and rejected-request
launcher/shim probes. these checks do not qualify provider behavior.

approved disposable mac native qualification passed on provider source `49c9f47`
and patch `1c0e9e659297069b384f7723828337cef8e6a82f43ff5aedc5ff44e4a74072d0`:
marked no-auth cold startup created the pinned account owner; a second tui
attached without restarting it or replacing the first selected view; read-only
native observation passed; spoofed-owner registration and cross-view guarded
control were rejected. no upstream update marker was created. the debug daemon
used approximately 188 mib rss; this is one fixture measurement, not production
capacity acceptance. all owned tmux sockets, provider processes and fixtures
were removed. real accounts and fleet hosts were untouched.

a focused disposable mac mismatch check also passed: an upstream owner and
patched challenger both reported 0.157.1 but had different executable digests.
the marked challenger exited 1 without changing the owner's pid, kernel lifetime,
record, package symlink or digest; the owner still served its version rpc.
no update marker existed. the exact owner was stopped through native lifecycle
control and all fixtures were removed.

approved devbox noble x86_64 namespace qualification passed using task-owned
canonical-package and native-daemon-copy paths. both copies matched distro
bubblewrap digest `e318903862396f96de3df57264e0158682b952fd3fb53ac23d876413e7b30f71`.
without the proposed policy, the native copy failed with permission denied while
the system binary passed. a unique temporary profile used the proposed brace
structure, flags and `userns` rule, narrowing release wildcards to task-owned
names. both copies then attached to that profile and created isolated user,
network and pid namespaces with uid 0 inside. the profile was unloaded and
absence verified; test directories and newly created empty parents were removed.
no existing profile, service, provider configuration or gateway was changed.

the permanent proposed profile is absent on the host. persistent activation,
full linux provider startup/control, authenticated native control and coordinated
gateway acceptance remain NOT_RUN. this namespace mechanism/path probe is not a
fleet deployment or full linux provider acceptance. remove this record after
those boundaries and the coordinated release pass.

coordinated release status: `assets/skidbladnir/release-pin.json` now selects
public v0.10.4 from `8510f2e`, with exact mac/linux artifact hashes. the mac
archive digest and release manifest match that declaration. combined isolated
gateway/helper/provider acceptance is still pending; retain `qualified: false`
until the accepted boundaries pass. the source deployment pin also records false;
only the installer's own declaration gates apply. qualification status is not
an embedded runtime compatibility check or a replacement for combined evidence.

host apply limit: ordinary ansible apply has no gateway role and does not run
provider preflight. it retires former shared services in pre-tasks, reconciles
base/jarvis/workspace/security/shell/github, then installs pinned ai binaries.
`qualified: false` guards only selected gateway apply; it is not an early host
admission gate and cannot prevent partial host mutation or binary upgrades.
keep this installer cutover unmerged until coordinated gateway release/pin and
combined provider acceptance are ready. existing host apply remains explicitly
nontransactional; an optional gateway flag must not become a global host gate.

source-build correction: the required code-mode host uses upstream's sandbox
v8 artifacts. installation authenticates the target manifest against the pinned
source tree, then verifies the archive and binding before locked cargo builds.
temporary component checks reject unavailable/tampered manifests, either payload
tamper and wrong/missing/extra entries; verified artifacts pass. the exact
installer release build remains NOT_RUN. a genuine debug host was built from
unchanged provider `49c9f47` using that upstream setup.

combined fixture status: published gateway readiness and agent session creation
pass. the first launch omitted fixture machine initialization; correcting that
setup error restores readiness. no selected native binding/listener is observed
yet; investigation is at the login-shell startup handoff. this is not combined
acceptance, and no native read/control success is claimed.

login-shell correction: mac bash 3.2 has no `BASHPID`; the startup hook
therefore remained pending. the guard now uses the original `$$` together with
`BASH_SUBSHELL == 0`. temporary red/green checks reproduce the old failure on
mac bash 3.2 and pass both bash versions with subshell startup rejected.
