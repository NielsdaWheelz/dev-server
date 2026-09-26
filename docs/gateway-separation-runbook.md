# independent gateway cutover

implementation and operator-reported qualification, 2026-09-25/26, from
dev-server baseline `8498933` through `7c4500d`. the root operator reports both
products deployed on macbook, devbox and arch after namespace handback.
the acceptance table distinguishes observed boundaries from unperformed ones.
ordinary host apply remains a separate operation: it also owns upstream herdr
and the worker environment. source checks, live evidence and their limits are in
[validation](gateway-separation-validation.md).

## owners and inputs

dev-server owns installation, host configuration, scoped skid commands,
service definitions, receipts, ingress and removal. app owners own executable
interfaces, release certification and phone acceptance. jarvis owns its worker
mapping and continuity. the root operator owns repository names, publication
and skid namespace handback. ordinary, herdr and skid providers keep
their existing homes, command behavior, integrations and state. jarvis's existing
worker map and cognition configuration remain intact; the proposed remap and
pr 42 are withdrawn. no provider state is moved, copied or reinitialized.

herdr-mobile `v0.9.0` is published from
`68a652d7ccbeaaf472ef1c5f3a4ea6949808bca4` and pinned in
`assets/herdr-mobile/release-pin.json`. the pin uses the documented conversion
from the app owner's five-asset `release-pin.json`: retain version and source,
map `darwinArm64Sha256` and `linuxAmd64Sha256` into the corresponding host
artifacts, and derive their canonical release-download urls. the deployment
does not consume the apk, signing-certificate or checksum-file digests.

original skid `v0.9.0` is published from
`580e0992d1ee0d7334cefc6561e7f55a5836baf5`. dev-server pin commit `ce6b96b`
converts upstream pin `50a688b` to the same host-only schema; both canonical
host archives, digests and manifests were verified. published pins do not
authorize live namespace handback. verify canonical repositories by numeric id:

```sh
gh api repos/NielsdaWheelz/herdr-mobile --jq '{id,full_name}'
gh api repos/NielsdaWheelz/skidbladnir --jq '{id,full_name}'
```

the required ids are respectively `1342599607` and `1386409483`. the root
handoff reports the github name transfer complete on 2026-09-25; local checkout
directory names remain unchanged. original skid's stale v0.6 pin is
inadmissible. the former skid v0.8 release belongs to the first repository.
publication belongs to the root operator and does not wait for live host
namespace handback. installation does. redirects are insufficient;
do not delete or recreate either repository if name reclamation fails.

original skid supplied its source deployment contract at
`/Users/nnandal/Documents/code/skid-v1/docs/dev-server-handoff.md` on
2026-09-25. implementation `3bd0ae468c8feefc1e2eac5ee72085d23ec445e2` adopts
existing accounts; coordinating handoff `2ad2cab` confirms that contract for
both products. templates are under `deployment/providers/` and the helper pin under
`deployment/native-control/pin.json`. the exact helper inputs are `llm-calling@ec97adeb9ddd0f91b141f89cc42cff7cc7efdb8f`, uv `0.11.28`,
python `3.12.13`, claude sdk `0.2.130`. the owner reports frozen installation, disposable-home/path routing and native
claude 2.1.282 command availability passing on macbook without authentication.
subsequent operator qualification passed native claude-work binding, idle
status and bounded history on all three hosts with the corrected plugin in
`7c4500d`. stop closed each test terminal but reported agent halt as
`unconfirmed`; later observation found the exact provider processes gone.
native background-job stop remains `NOT_RUN`. provider upgrades require
requalification; an exact install alone cannot prove compatibility.

## deployment contract

| surface | herdr-mobile | original skid |
| --- | --- | --- |
| command | `herdr-mobile` | `skidbladnir` |
| launcher | `herdr-mobile-launch` | `skidbladnir-launch` |
| linux user unit | `herdr-mobile.service` | `skidbladnir.service` |
| mac label | `dev.niels.herdr-mobile` | `dev.niels.skidbladnir` |
| config, data, state leaf | `herdr-mobile` | `skidbladnir` |
| loopback | `127.0.0.1:7342` | `127.0.0.1:7341` |
| private serve handler | `:8444/v1` | `:8443/v1` |
| receipt stems | `herdr-mobile.runtime`, `herdr-mobile.unit` | `skid.runtime`, `skid.unit` |
| machine header | `Herdr-Mobile-Machine` | `Skidbladnir-Machine` |

each product owns its generations, artifact cache, credentials and private
operator `client.json`. neither owns the other's resources. android signing
files remain under their app owner's control and outside gateway validation.
upstream `herdr`, its service, config, socket and runtime identity remain
upstream herdr's. stopping/removing a gateway never stops herdr or tmux.

ordinary `./workstation apply|upgrade` and `./devbox apply|upgrade` provision
shared host tools and upstream herdr. gateway maintenance is selected:

```sh
./workstation gateway apply herdr-mobile
./workstation gateway apply skidbladnir
./devbox gateway apply herdr-mobile
./devbox gateway apply skidbladnir
```

replace `apply` with `remove` for scoped gateway removal. run workstation
commands on the target workstation; the devbox command addresses the existing
devbox through its strict deployment connection. provider executable upgrades
remain a separate host operation. the other gateway may be absent.

devbox uses the existing `dev-server-deploy` principal's elevation for tailscale
ingress. its root preflight runs before user runtime apply/remove; the gateway
stays owned by `niels`, including its user service, home and dbus environment.
only after that operation succeeds does a separate root task reconcile the
selected handler. root ingress uses the system command path and the two
deployment-owned libraries in `/usr/local/libexec/dev-server-gateway`, not
the user's runtime copies. no tailscale
operator permission is granted to `niels`, and workstation elevation is unchanged.
an action from preflight or runtime defers subsequent tasks. a later ingress
failure remains an error; it does not undo a verified gateway operation. resolve
the reported host-level failure and rerun the same selected operation.

ingress operations affect only the selected `/v1` handler. unrelated handlers,
including handlers on the same port, must survive. public funnel on that
origin is a failure. manual removal, when an operator has verified ownership,
uses `tailscale serve --https=8444 --set-path=/v1 off` for herdr-mobile or
`tailscale serve --https=8443 --set-path=/v1 off` for skid. on devbox, issue these
through the deployment principal with `sudo`, not from unprivileged `niels`.
never use
`tailscale serve reset` or port-wide cleanup. this uses the supported
[serve command](https://tailscale.com/docs/reference/tailscale-cli/serve).

## provider and jarvis contract

the host owner is `/Users/nnandal` on macbook, `/home/nnandal` on arch, and
`/home/niels` on devbox. join the target owner's home with the following
existing relative values in jarvis `src/jarvis/agent_tools.py`:

| selection | kind | variable | relative value |
| --- | --- | --- | --- |
| personal | codex | `CODEX_HOME` | `.codex` |
| work | codex | `CODEX_HOME` | `.codex-work` |
| work2 | codex | `CODEX_HOME` | `.codex-work2` |
| claude-work | claude | `CLAUDE_CONFIG_DIR` | `.claude-work` |
| manual/native claude default | claude | unset by default | native `.claude` / `.claude.json` state |

the gate retains its existing four explicit home values and command allowlist.
personal claude is a native/manual default, not a fifth phone profile. bare
claude uses its native executable; the existing codex account launcher preserves
explicit `CODEX_HOME` for bare codex and named work commands retain their account
selection semantics. ordinary shell aliases and explicit environment overrides
keep their established behavior. these are shared user homes with existing
auth, configuration, history, memories, plugins, trust and native herdr hooks.

original skid uses the same four explicit account homes. manual personal
claude leaves `CLAUDE_CONFIG_DIR` unset; setting it to `~/.claude` is not
assumed equivalent to native default behavior. its forge profiles invoke absolute
native providers with explicit arguments, foreground signatures and its
claude identity plugin. codex must resolve to its packaged native executable,
not the npm javascript entry point. claude keeps basename `claude` for helper
lookup. its host config includes `nativeControlPath` pointing
to the skid-owned helper. the gateway supplies its selected absolute claude
command through `SKIDBLADNIR_CLAUDE_COMMAND`; the frozen environment's private
`bin/claude` shim executes that command and removes the dispatch variable.
missing native executable or shim fails without searching account wrappers.
herdr-mobile uses the reduced herdr/profile schema
and no helper or skid hooks. each admitted binary validates its own schema.

original skid installs its supplied `provider-command` and `shell-init` under
`current/providers/`. new terminals set `SKIDBLADNIR_SHELL=1` and
`CODEX_HOME=HOME/.codex`, clearing `CLAUDE_CONFIG_DIR` and inherited herdr
context. source `shell-init` at
the end of ordinary startup; it replaces shared aliases with absolute product
functions. bash login uses the first existing `.bash_profile`, `.bash_login`
or `.profile`, while interactive subshells use `.bashrc`; zsh reads `.zshrc`
and then `.zlogin` for login shells. qualify both startup paths. the launcher
clears the opposite provider home and shell marker, sets `SKIDBLADNIR_AGENT=1`
at provider exec, and passes codex `--yolo` or claude
`--dangerously-skip-permissions --plugin-dir <skid-plugin>`.

skid apply owns this startup setup; shared provider installation does not
validate or edit these files. existing startup symlinks are followed to their
regular targets without replacing the links or unrelated bytes/modes. the
managed zsh template retains its inert guard so a later dotfile apply preserves
the integration; skid setup avoids a duplicate source. this leaves one small
product-aware guard in the shared template instead of introducing a shell
extension framework. each startup phase re-sources after its own configuration;
later login aliases cannot undo the scoped commands.

herdr's service adds no provider-home overrides and provisions no private homes.
its native integrations remain in the existing accounts. an explicit forge
profile must survive shell startup. before apply, qualify ordinary/herdr
bare/account commands and marked-skid commands using disposable bash/zsh homes
and fake executables for the macos and linux entry paths.

skid installs no codex hooks and never writes provider instructions/settings.
its explicit claude plugin accepts only `Claude SessionStart` with
`SKIDBLADNIR_AGENT=1` and no `HERDR_ENV=1`, rejecting foreign launches before
reading input/config. the app still checks pane, tty, pid and process lifetime.
gateway, terminal and helper boundaries clear inherited exec markers.
the plugin uses [exec form](https://code.claude.com/docs/en/hooks#exec-form-and-shell-form):
`args: []` keeps the executable path literal, so `command` must not contain
shell quotes. changing this plugin file creates a new ten-file generation;
apply that generation and qualify a new claude session. gateway binary/archive
pins do not change, and rollback restores the prior plugin with its runtime.
never copy credentials, history, discovery sockets, account trees, plugin
caches or trust records. existing account state is shared across apps: a
provider configuration or history change in one is visible in the others.
actual hooks at home and a shared project require qualification at the
integration boundary; separate directories would not establish correct hook
targeting. the acceptance table records the observed scope.

## ordered host cutover

the root operator completed the namespace transition below on all three hosts.
these steps describe the one-time transition; do not repeat old-namespace
retirement on an installed separated product.

perform these stages host by host, recording macbook, devbox and arch separately.
use an operator control shell independent of the gateways being replaced. keep
content-free evidence only: identities, hashes, modes, counts and pass/fail.
never retain terminal bytes, objectives, provider account data or credentials.

1. privately save the old v0.8 artifact and exact unit/launcher/config inputs
   needed during the transition. record their identities without reading
   secrets into logs. inventory current/previous links, receipts, both ports,
   service labels, private signing-file preservation checks and cognition service
   pids. report only pass/fail for signing preservation, never key contents.
   inspect the old gateway's release manifest to prove it is the herdr-backed
   product. do not classify by the `skidbladnir` basename alone.
2. confirm the new published herdr-mobile pin and interface contract. stage
   herdr-mobile under its new namespace with fresh bearer and random machine handle, then
   its `8444/v1` ingress. retain the old gateway and `8443` during transition.
   verify tailnet policy permits the new port; an empty local port proves
   nothing about phone reachability.
3. activate the new gateway against the unchanged supervised herdr runtime.
   preserve its session snapshot, workers, provider homes, native integrations
   and jarvis map/gate; verify the existing socket/config identity. missing
   renamed mobile metadata is acceptable and needs no reset or compatibility
   reader. a separately necessary herdr service change needs its own stated
   reason and worker coordination; gateway replacement alone provides none.
   do not stop cognition, kill tmux sessions or change the default server's
   environment. provider-state cleanup and fresh authentication are not part
   of this transition.
4. the app/phone owner installs the new herdr phone app and proves pairing,
   launch, attachment, input and stop against every host. create a private
   herdr-mobile fleet `client.json`; never reuse the old product's file.
   complete all five manual/native defaults and four forge profile checks
   before releasing the old namespace.
5. inventory and retire the OLD herdr-backed skid deployment only after step
   4 passes everywhere. stop its gateway; remove only its `8443/v1` mapping,
   old gateway unit, launcher/command links, bearer, machine handle, old
   operator client and `skid.*` receipts, then its verified old gateway
   generations/artifacts/unit generations. preserve signing files and every
   unrelated file in `.config/skidbladnir`. do not recursively delete that
   directory or the skid data root. a separated-product remove command must
   reject the old v0.8 namespace; this one-time retirement is operator-owned.
6. remove only verified obsolete skid integration entries/scripts from the
   ordinary `.codex`, `.codex-work`, `.codex-work2`, `.claude` and
   `.claude-work` homes. use parsed hook/settings entries and exact installed
   script identities; preserve native herdr integrations, user hooks/settings
   and all credentials, histories, plugins and trust.
   inspect codex inline/plugin hook sources too, including `.codex/hooks.json`
   discovered at `cwd=$HOME`. unknown entries are a blocker for the operator,
   not permission to delete the entire file or relocate providers.
7. the root operator explicitly records namespace handback. only then admit
   original skid's independently published release and qualified helper,
   mint its fresh gateway credentials, apply its gateway and `8443/v1`
   ingress. the phone owner clears only the obsolete skid android package's
   app data, installs the increasing original-product release and pairs fresh.
   original skid retains its signing identity. do not activate an unfinished
   app build or reclaim a namespace by overwriting its old contents.

## recovery boundary

before handback, the root operator may restore the privately saved old gateway
inputs in the old namespace. do not apply an old whole dev-server revision:
it also owns shared wrappers, hook retirement and host services.

after handback, herdr-mobile recovery remains entirely in `herdr-mobile`.
original skid recovery remains entirely in `skidbladnir`; herdr-backed v0.8
is never an original skid rollback target. the first separated release may
have no previous separated release: stop and repair within its namespace.
later releases retain only their own verified rollback chain. never restore
gateway credentials or signing state from another product; provider accounts
remain shared user state outside gateway recovery.

the helper launcher is part of skid's immutable gateway generation; its stable
command follows `current`. a failed gateway activation therefore restores the
matching helper launcher too. immutable helper environments remain at their
original paths because moving a built python environment breaks executable
and editable-package paths. provider accounts and their mutable login, history,
trust and settings remain persistent; gateway rollback does not revert them.

runtime and unit have one atomic verified-pair receipt. the two familiar digest
stems remain informational, preserving the published receipt names at the cost
of one small authoritative pair file. new installs also record a product
`deployment-identity` before minting credentials; unmarked old state is refused.

gateway rollback means applying that product's last verified declaration and
pin with the current scoped installer; never point a symlink at an arbitrary
old generation. a candidate that cannot be stopped retains its inputs and
recovery stage for operator repair. do not move executable/config inputs
under a process whose stop is unconfirmed.

the legacy gateway retirement inventory is confined to:

- macbook `Library/LaunchAgents/dev.niels.skidbladnir.plist`, or linux
  `.config/systemd/user/skidbladnir.service` and its enablement link;
- `.local/bin/skidbladnir` and `.local/bin/skidbladnir-launch`, after checking
  their old owned target/bytes; any historical `skid` or `skid-notify` residue
  requires separate exact-content inventory;
- `.config/skidbladnir/{bearer,machine-handle,client.json}` only;
- `.local/state/dev-server/active/skid.runtime.sha256` and
  `skid.unit.sha256`, plus old gateway-only logs under `.local/state/skidbladnir`;
- `.local/share/skidbladnir/{current,previous}` and the old gateway's individually
  verified `releases`, `artifacts`, `units` and recovery-stage children.

all deletions use explicit inspected paths. no recursive deletion of the config,
data or state root is justified by this inventory. old whole-host recovery is
retired at namespace handback; retain the private old inputs only for the
pre-handback recovery window.

obsolete skid hook removal uses these exact historical predicates. native herdr
integration commands/scripts remain in place:

- codex homes: `.codex`, `.codex-work`, `.codex-work2`, and historical
  `.codex-personal`. remove individual `SessionStart[].hooks[]` entries whose
  command exactly equals the rendered old skid command
  `HOME/.local/bin/skidbladnir agent-hook --host-config=HOME/.local/share/skidbladnir/current/host-config.json Codex SessionStart`.
- from codex `config.toml`, remove only the exact old
  `notify = ["HOME/.local/bin/skid-notify"]` line. leave `[features] hooks = true`
  and all other settings intact.
- remove an obsolete skid hook script only after its contents match the
  inventoried historical skid installation and no retained hook refers
  to it. write parsed json atomically while retaining unrelated keys, sibling
  hooks and groups. do not reuse the historical group-level removal script:
  a matching group may also contain user hooks.

`HOME` above means the inspected absolute owner path;
compare the actual serialized command, not a substring or product-name match.
inline/project/plugin sources require a separate content-free audit at home
and the selected shared project. an unknown reference stays in place and
blocks isolation acceptance until its owner resolves it.

## generation receipt contract

the deployment hashes each file as `relative-name + NUL + lowercase-sha256 +
newline`, concatenates those records in the order below, then hashes the
concatenation. the result is the generation directory suffix and
`active/<receipt>.runtime.sha256` value. receipts are mode `0600`, generation
directories `0700`. admission requires that mode and equality between the
computed digest and directory suffix. herdr-mobile has four files:

1. `herdr-mobile` (`0755`)
2. `characters.json` (`0644`)
3. `release.json` (`0644`)
4. `host-config.json` (`0600`)

original skid has ten, in this exact order:

1. `skidbladnir` (`0755`)
2. `characters.json` (`0644`)
3. `release.json` (`0644`)
4. `host-config.json` (`0600`)
5. `providers/native-control` (`0755`)
6. `providers/provider-command` (`0755`)
7. `providers/shell-init` (`0644`)
8. `providers/claude-agent-identity/.claude-plugin/plugin.json` (`0644`)
9. `providers/claude-agent-identity/hooks/hooks.json` (`0644`)
10. `providers/claude-agent-identity/bin/agent-hook` (`0755`)

the helper launcher names a separately pinned immutable environment. its shim,
entry point, source commit, lock and installed versions are checked before
activation. the plugin and helper launcher follow the gateway's `current`
pointer, so failed activation restores them together. this costs four more
hashed files and retains private helper environments; it avoids independently
switching dependencies underneath a verified gateway.

the original app's `docs/dev-server-handoff.md` and `scripts/fleet` implement
this exact ten-file order, encoding and modes, inspected on 2026-09-25 in
`/Users/nnandal/Documents/code/skid-v1`. fleet verification requires the computed
digest, directory suffix and active runtime receipt to agree. host archive
digests and archive contents are unchanged by this deployment-only contract.
dev-server acknowledges that contract: admission now rejects a wrong directory
mode or computed suffix for either product. disposable checks against the
original fleet verifier and prior-generation restore passed; native lifecycle
qualification remains separate. see [validation](gateway-separation-validation.md).

helper environments are never pruned by gateway apply or removal. this
conservatively preserves every retained generation's dependency at the cost of
disk space; automatic helper-environment collection is deferred. any future
cleanup must account for every retained generation and recovery stage before
removing a revision.

## acceptance and evidence

on disposable installations first: independent first/repeat apply with the
other absent; two concurrent deployments; failed upgrade restores the verified
prior; interrupted activation never combines an unverified runtime/unit pair;
rollback leaves a distinct previous or no previous; removal preserves the
other product and unrelated signing/provider/project files. service stand-ins
qualify installer control flow, not native supervisors or provider behavior.

the root operator's [qualification record](https://github.com/NielsdaWheelz/herdr-mobile/blob/0dd92df41090c156b53bc8632c4b34281d3b32ce/docs/separation-qualification.md)
supplies live results against dev-server `7c4500d`.
these are operator-reported results, separate from this source task's fixtures:

| boundary | macbook | devbox | arch | owner / blocker |
| --- | --- | --- | --- | --- |
| both gateways healthy; both fleet verifiers | PASS | PASS | PASS | root / independent v0.9.0 releases |
| selected repeat apply makes no changes | PASS | PASS | PASS | root / corrected generation |
| four forge + five manual routes at home/shared checkout, each product | PASS | PASS | PASS | app / eighteen routes per product and host |
| concurrent codex/claude in both products; disjoint inventories | PASS | PASS | PASS | app / existing accounts, isolated runtime context |
| native claude-work binding, idle status and bounded history | PASS | PASS | PASS | original / deployed binary/plugin; probe scope below |
| skid hook rejects actual herdr context before reading input | PASS | NOT_RUN | NOT_RUN | original / native mac probe; all-host context checks above |
| pre-cutover codex/claude-work history files remain accessible | PASS | PASS | PASS | app / read-only access, no conversation resume |
| both phone apps paired, attached and accepting paced input | PASS | PASS | PASS | phone / production gateways |
| cross-product bearer rejected 401; wrong machine header 409 | PASS | PASS | PASS | app / mobile activation and original before plugin correction |
| both restart directions preserve opposite worker/phone attachment/input | NOT_RUN | NOT_RUN | PASS | root + phone / arch lifecycle probe |
| original prior-generation rollback and corrected restore | NOT_RUN | NOT_RUN | PASS | root / actual prior generation through current installer |
| mobile repeat apply preserves opposite original phone attachment/input | NOT_RUN | NOT_RUN | PASS | root + phone / unchanged declaration, no forced reinstall |
| mobile prior separated-release rollback | UNAVAILABLE | UNAVAILABLE | UNAVAILABLE | first separated release; no prior target |
| native scoped removal preserves other ingress/files | NOT_RUN | NOT_RUN | NOT_RUN | disposable installer proof only |

original's mac provider probes used exact test-owned production sessions;
linux used isolated runtimes with the deployed binary/plugin. mobile provider
probes and all phone checks used production gateways. route selection does
not establish provider readiness or authentication for every account.
native stop reported truthful closed/unconfirmed results, followed by exact
provider-process exit observations, on every host.

both apk reinstall directions preserved the opposite app's pairing and phone
use; the mobile reinstall check retained original's devbox attachment/input.
arch original rollback selected the actual prior quoted-plugin generation and
then restored the correction. opposite workers, snapshot, owned files, both
ingress mappings and subsequent phone input survived. this proves generation
recovery, not release-version rollback.
upstream herdr's config, socket, workers and service identity were preserved
on every host; devbox jarvis and its three cognition services retained their
identities. this does not establish a new cognition turn or a resumed historical
conversation.

independent first/repeat apply with the other product absent, failed-upgrade
recovery and scoped removal passed disposable installer probes. those results
do not claim native removal or unavailable mobile version rollback. the final
arch mobile repeat apply returned up to date while original's phone remained
attached; runtime/worker identities, protected files, cognition and ingress
were unchanged, and explicitly focused original phone input passed afterward.
both apps' phone interrupt dispatch and exact-target stop passed. all test-owned
phone resources were absent from the six final inventories; pre-existing mac
sessions remained. native probe resources/scripts were removed. both final
fleet verifiers passed on all three hosts. the coordination issue is closed;
the unperformed boundaries above retain their stated limits.

during source preparation, tmux probes may mutate only resources they create
on an isolated `-L` socket.
no default-server mutations, device changes or live resets were performed as
part of source preparation.
