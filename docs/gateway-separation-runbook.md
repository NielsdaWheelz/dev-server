# independent gateway cutover

source preparation, 2026-09-25. this is an operator runbook, not a record of
live completion. the implementation starts from dev-server `8498933`.
all live acceptance below is `NOT_RUN` until the responsible operator records
its result. do not run ordinary host apply during source preparation: it also
owns upstream herdr and the worker environment.
completed source checks and their limits are recorded in
[validation](gateway-separation-validation.md).

## owners and inputs

dev-server owns installation, host configuration, private provider homes,
service definitions, receipts, ingress and removal. app owners own executable
interfaces, release certification and phone acceptance. jarvis owns its worker
mapping and quiescence. the root operator owns repository names, publication,
the herdr reset and skid namespace handback. no step changes cognition's
account declarations, discovery sockets, credentials or services.

herdr-mobile `v0.9.0` is published from
`68a652d7ccbeaaf472ef1c5f3a4ea6949808bca4` and pinned in
`assets/herdr-mobile/release-pin.json`. the pin uses the documented conversion
from the app owner's five-asset `release-pin.json`: retain version and source,
map `darwinArm64Sha256` and `linuxAmd64Sha256` into the corresponding host
artifacts, and derive their canonical release-download urls. the deployment
does not consume the apk, signing-certificate or checksum-file digests.

original skid's published pin remains required before its activation: version,
source commit, archive url and sha256 for both platforms. never fill these
fields from an anticipated release. verify canonical repositories by numeric id:

```sh
gh api repos/NielsdaWheelz/herdr-mobile --jq '{id,full_name}'
gh api repos/NielsdaWheelz/skidbladnir --jq '{id,full_name}'
```

the required ids are respectively `1342599607` and `1386409483`. the root
handoff reports the github name transfer complete on 2026-09-25; local checkout
directory names remain unchanged. original skid's stale v0.6 pin is
inadmissible. the former skid v0.8 release belongs to the first repository.
publication belongs to the root operator. redirects are insufficient;
do not delete or recreate either repository if name reclamation fails.

original skid supplied its source deployment contract at
`/Users/nnandal/Documents/code/skid-v1/docs/dev-server-handoff.md` on
2026-09-25, with templates under `deployment/providers/` and helper pin under
`deployment/native-control/pin.json`. the exact helper inputs are `llm-calling@ec97adeb9ddd0f91b141f89cc42cff7cc7efdb8f`, uv `0.11.28`,
python `3.12.13`, claude sdk `0.2.130`. the owner reports frozen installation, private-home/path routing and native
claude 2.1.282 command availability passing on macbook without authentication.
live status/history/stop remain `NOT_RUN` on all hosts. provider upgrades require
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

ingress operations affect only the selected `/v1` handler. unrelated handlers,
including handlers on the same port, must survive. public funnel on that
origin is a failure. manual removal, when an operator has verified ownership,
uses `tailscale serve --https=8444 --set-path=/v1 off` for herdr-mobile or
`tailscale serve --https=8443 --set-path=/v1 off` for skid. never use
`tailscale serve reset` or port-wide cleanup. this uses the supported
[serve command](https://tailscale.com/docs/reference/tailscale-cli/serve).

## provider and jarvis contract

the host owner is `/Users/nnandal` on macbook, `/home/nnandal` on arch, and
`/home/niels` on devbox. join the target owner's home with the following
relative values in jarvis `src/jarvis/agent_tools.py`:

| selection | kind | variable | relative value |
| --- | --- | --- | --- |
| personal | codex | `CODEX_HOME` | `.local/share/herdr/providers/codex-personal` |
| work | codex | `CODEX_HOME` | `.local/share/herdr/providers/codex-work` |
| work2 | codex | `CODEX_HOME` | `.local/share/herdr/providers/codex-work2` |
| claude-work | claude | `CLAUDE_CONFIG_DIR` | `.local/share/herdr/providers/claude-work` |
| manual/native claude default | claude | `CLAUDE_CONFIG_DIR` | `.local/share/herdr/providers/claude-personal` |

the gate accepts these exact home values, including explicit personal claude.
its command allowlist is unchanged. retain the phone's four forge profiles;
personal claude is a native/manual default. do not change jarvis cognition's
ordinary `.codex*` homes or discovery paths. this checkout cannot implement
the jarvis-side map. that owner has prepared the matching map in `bada736`
([draft pr 42](https://github.com/NielsdaWheelz/jarvis/pull/42)); source inspection
confirms the four profile values above. local verification passed according to
its handoff; hosted checks are blocked by the recorded account billing limit.
merge/deployment and settlement of pending incompatible worker actions remain
jarvis-owned cutover prerequisites.

original skid uses the same five child names beneath
`.local/share/skidbladnir/providers/`. its forge profiles invoke absolute
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
`current/providers/`. new terminals set `SKIDBLADNIR_SHELL=1` and both personal
home defaults after clearing inherited herdr context. source `shell-init` at
the end of ordinary startup; it replaces shared aliases with absolute product
functions. bash login uses the first existing `.bash_profile`, `.bash_login`
or `.profile`, while interactive subshells use `.bashrc`; zsh reads `.zshrc`
and then `.zlogin` for login shells. qualify both startup paths. the launcher
clears the opposite provider home and shell marker and passes codex `--yolo`
or claude `--dangerously-skip-permissions --plugin-dir <skid-plugin>`.

herdr service defaults seed both private personal homes; explicit pane profiles
replace the relevant home. its wrappers retain selected homes and work commands
stay under herdr. cognition's existing home declaration and operational inputs
remain unchanged.

homes start fresh. install only the product's instructions/settings and its
own integrations. login through normal provider setup and trust the inspected
hooks. never copy credentials, history, discovery sockets, account trees,
plugin caches or trust records. a missing login/trust is a prerequisite,
not a successful provider launch.

## ordered host cutover

perform these stages host by host, recording macbook, devbox and arch separately.
use a control shell outside the herdr panes that will be discarded. keep
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
   nothing about phone reachability. provider launch acceptance follows the
   coordinated worker-environment change in step 3.
3. jarvis's owner settles pending worker actions and quiesces worker creation.
   the root operator stops only the intended supervised herdr runtime, waits
   for it to stop, and then discards its old session snapshot. restarting
   without removing that stopped runtime's snapshot can restore old shells.
   do not stop cognition, kill unrelated tmux sessions or change the default
   tmux server's environment. apply the matching herdr provider defaults,
   gate, worker map and gateway. restart through the supervisor and verify
   the existing herdr socket/config identity. discarded panes need no recovery.
   ordinary host apply provisions the five fresh homes and pinned integrations;
   complete each home's normal login/trust before releasing worker creation.
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
6. remove only inventoried old product integration entries/scripts from the
   ordinary `.codex`, `.codex-work`, `.codex-work2`, `.claude` and
   `.claude-work` homes. use parsed hook/settings entries and exact installed
   script identities; preserve unrelated hooks/settings and all credentials.
   inspect codex inline/plugin hook sources too, including `.codex/hooks.json`
   discovered at `cwd=$HOME`. unknown entries are a blocker for the operator,
   not permission to delete the entire file. recurring product installers
   never own these ordinary or project hook files.
7. the root operator explicitly records namespace handback. only then admit
   original skid's independently published release and qualified helper,
   provision its fresh homes/credentials, apply its gateway and `8443/v1`
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
gateway credentials, signing state or provider homes from another product.

the helper launcher is part of skid's immutable gateway generation; its stable
command follows `current`. a failed gateway activation therefore restores the
matching helper launcher too. immutable helper environments remain at their
original paths because moving a built python environment breaks executable
and editable-package paths. private provider homes and their mutable login,
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

the exact upstream herdr stop is `launchctl bootout gui/$(id -u)/dev.niels.herdr`
on macbook, or `systemctl --user stop herdr.service` on arch/devbox as the owner
account. verify the exact label/unit is inactive and the managed socket has no
listener before moving aside `.config/herdr/session.json`. do not run bare
`herdr` between stop and apply. this command ends herdr panes and must be issued
from the external control shell during the coordinated window.

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

legacy hook removal uses these exact predicates, confirmed from history and a
disposable installation of pinned herdr's integrations:

- codex homes: `.codex`, `.codex-work`, `.codex-work2`, and historical
  `.codex-personal`. remove individual `SessionStart[].hooks[]` entries whose
  command exactly equals the rendered old skid command
  `HOME/.local/bin/skidbladnir agent-hook --host-config=HOME/.local/share/skidbladnir/current/host-config.json Codex SessionStart`
  or pinned herdr's `bash 'ACCOUNT/herdr-agent-state.sh' session`.
- claude `.claude` and `.claude-work`: remove only the herdr `SessionStart`
  hook command `bash 'ACCOUNT/hooks/herdr-agent-state.sh' session`, with matcher
  `^(startup|resume|clear|compact|fork)$`.
- from codex `config.toml`, remove only the exact old
  `notify = ["HOME/.local/bin/skid-notify"]` line. leave `[features] hooks = true`
  and all other settings intact.
- remove an obsolete hook script only after its contents match the script from
  a disposable installation of the pinned runtime and no retained hook refers
  to it. write parsed json atomically while retaining unrelated keys, sibling
  hooks and groups. do not reuse the historical group-level removal script:
  a matching group may also contain user hooks.

`HOME` and `ACCOUNT` above mean the inspected absolute owner/account paths;
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

on each live platform, the root operator and app/jarvis owners must record:

| boundary | macbook | devbox | arch | owner / blocker |
| --- | --- | --- | --- | --- |
| both gateways healthy concurrently | NOT_RUN | NOT_RUN | NOT_RUN | root / original skid pin and handback |
| repeat apply and independent absent-product apply | NOT_RUN | NOT_RUN | NOT_RUN | root / staged releases |
| restart, reinstall, rollback preserve other workers/attachments | NOT_RUN | NOT_RUN | NOT_RUN | app + root / live window |
| all forge/manual profiles use correct home/hooks | NOT_RUN | NOT_RUN | NOT_RUN | app + root / fresh login and trust |
| launch from opposite runtime, home and shared project | NOT_RUN | NOT_RUN | NOT_RUN | app + root / runtime creation contract |
| cognition service/history continuity | NOT_RUN | NOT_RUN | NOT_RUN | jarvis / worker-map activation and quiescence |
| phone reaches 8444; wrong-product auth rejected | NOT_RUN | NOT_RUN | NOT_RUN | app + phone / releases and tailnet policy |
| scoped removal preserves other ingress/files | NOT_RUN | NOT_RUN | NOT_RUN | root / disposable native qualification |

tmux probes may mutate only resources they create on an isolated `-L` socket.
no default-server mutations, device changes or live resets were performed as
part of source preparation. unresolved prerequisites are tracked in
[gateway separation](issues/gateway-separation.md).
