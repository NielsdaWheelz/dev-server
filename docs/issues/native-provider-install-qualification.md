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

remaining live boundaries are NOT_RUN: ubuntu noble x86_64 namespace creation
from both the source package and native daemon's bundled bubblewrap copy;
existing mismatched package refusal on a live owner; authenticated native
control; and the coordinated gateway release. the preexisting ubuntu 26.04 arm
vm was left untouched and does not qualify the devbox boundary. remove this
record after these accepted boundaries and the coordinated release pass.

coordinated release blocker: `assets/skidbladnir/release-pin.json` still selects
v0.10.3 (`e5906e4`), while the new helper and host declaration use the revised
native-control contract. provider preflight checks `qualified` before gateway
staging; it does not bind helper protocol compatibility to a gateway release.
the admitted binary validates host config later, which cannot prove the helper
protocol agrees. do not enable qualification merely after isolated helper tests.
first publish the coordinated skid release, update its immutable artifact/source
pin, and qualify that gateway with these exact provider/helper inputs. retain
`qualified: false` until all three conditions hold; release publication is
outside this integration assignment.

host apply limit: ordinary ansible apply has no gateway role and does not run
provider preflight. it retires former shared services in pre-tasks, reconciles
base/jarvis/workspace/security/shell/github, then installs pinned ai binaries.
`qualified: false` guards only selected gateway apply; it is not an early host
admission gate and cannot prevent partial host mutation or binary upgrades.
keep this installer cutover unmerged until coordinated gateway release/pin and
combined provider acceptance are ready. existing host apply remains explicitly
nontransactional; an optional gateway flag must not become a global host gate.
