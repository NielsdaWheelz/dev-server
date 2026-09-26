# gateway separation source validation

2026-09-25, against dev-server baseline `8498933`. temporary probes were
removed; no test framework or ci workflow was added. fixtures and service
stand-ins establish installer behavior only. live acceptance belongs to the
cutover operator.
the provider-routing correction follows owner handoff `7da90d8`: ordinary and
herdr accounts retain their existing homes and state. the earlier private
herdr-home proposal is withdrawn; its earlier fixture results are not routing
acceptance for this correction. coordinating handoff `2ad2cab` extends existing
accounts to skid using original implementation `3bd0ae4`. its former
private-home probes are historical, not acceptance for the revised routing.

## checks completed

| check | result and scope |
| --- | --- |
| static checks | bash/zsh syntax, shellcheck, json/plist parsing, herdr gate python syntax, and `git diff --check` passed |
| ansible | ordinary apply and selected gateway playbooks passed syntax checks; disposable callback probe rejects silent exit 2 and accepts exit 2 with an action |
| app config contracts | corrected existing-home mobile configs render for macos/linux and pass the available mac app validator; the mobile handoff reports the published v0.9.0 binary accepts these homes; original skid's real mac renderer output passes its validator built from the `3bd0ae4` implementation; native linux execution remains unrun here |
| published mobile pin | documented conversion preserves v0.9.0, source `68a652d7ccbeaaf472ef1c5f3a4ea6949808bca4`, and both host digests; github confirms canonical repository id `1342599607`, immutable release and exact tag commit; downloaded archives pass digest, member and manifest checks, and native mac version/config validation |
| published original pin | `ce6b96b` converts upstream `50a688b` to the host schema for v0.9.0 source `580e0992d1ee0d7334cefc6561e7f55a5836baf5`; canonical repository id `1386409483`, immutable release and tag agree; both downloaded host archives pass digest/member/manifest checks, native mac version matches, and the deployment parser accepts all three platforms |
| selected commands | invalid input rejected; selected pending pins return action/2 before product-home mutation, regardless of the other gateway's invalid port; absent removal needs no release pin or provider assets |
| ingress | a fake tailscale cli verified selected handler apply/remove while preserving the other port and an unrelated same-port handler; foreign handlers and public exposure on the selected origin refused |
| devbox ingress privilege | old `ce6b96b` task reproduces runtime mutation followed by a denied user write on apply/remove; corrected rendered tasks pass both products and repeat paths with that same restriction; only root tasks run ingress using root-owned libraries/system path; opposite-port and same-port handlers and unrelated funnel state are preserved |
| devbox ingress failures | preflight actions/public exposure stop before runtime; runtime actions/hard failures prevent ingress; silent exit 2 is rejected and actual write failures remain errors for apply/remove; these are disposable task/cli probes, not native sudo or tailscale qualification |
| independent installer lifecycle | each product passed disposable first install, repeat apply, forced failed-upgrade recovery and removal with the other absent |
| coinstalled isolation | both products in one disposable home retained identical opposite-product trees, links, units, receipts/pairs and simulated running state after selected repeat, failed upgrade and removal in both directions |
| receipts and recovery | interrupted promotion restores the atomic verified runtime/unit pair; duplicate previous pointer clears; failed retry of an unpaired first candidate returns to no active runtime |
| generation admission | before the correction, both products admitted mode `0755` and a wrong digest suffix; afterward intact `0700` generations pass and both alterations fail; original skid's actual fleet verifier agrees |
| admitted rollback prior | wrong mode or suffix on `previous` fails installed-generation admission; an intact prior restores current, unit and helper/plugin selection with its verified pair and fleet receipt preserved, using only supervisor/health stand-ins |
| unconfirmed stop | forced activation and stop failure preserved the candidate inputs, prior verified pair and one recovery stage; the other product remained unchanged |
| signing boundary | both product validators ignored and preserved unrelated signing paths, including deliberately invalid signing-file shapes |
| namespace boundary | unmarked legacy skid bearer refused and preserved; receipt names support herdr-mobile while rejecting malformed/path-traversal names |
| ordinary/herdr routing | wrappers, alias definitions and profile installation match baseline `8498933`; eight disposable mac/linux bash/zsh interactive/login entry paths retain normal homes, explicit bare-command overrides and forge selections; named work commands keep their original account selection; bare claude remains native |
| provider-state preservation | fake account settings/hooks/auth sentinels remain byte-identical; no private herdr home or bare claude wrapper is created; the fake herdr integration sees only existing normal homes and leaves its installed native hooks intact |
| shared installer ownership | real `ai_install` from `1296309` fails with action/2 on a valid symlinked bash login file; corrected installation passes with only native downloads/preflight stubbed and leaves the link, target bytes and mode unchanged |
| skid shell setup | disposable real setup preserves symlink identity, unrelated bytes and modes, is idempotent, and keeps one source per file; bash/zsh interactive and login shells restore scoped commands after late aliases, while unmarked and genuine herdr shells skip skid file access |
| skid account preservation | real renderer/provider-apply callback, with only helper installation stubbed, preserves bytes/modes of 21 fake account auth/settings/hooks/history and `.claude.json` sentinels; no private provider homes or codex hook file are created |
| scoped skid commands | all five rendered account commands select existing homes, leave personal claude's home variable unset, preserve flags/quoted arguments, set the provider-exec marker and scrub inherited runtime context; real callback startup passes bash/zsh interactive/login routing and the herdr guard |
| skid hook boundary | actual app binary silently skips foreign/herdr hooks before reading missing config; malformed marked input reports a content-free failure without blocking startup; live authenticated hook publication remains unrun |
| claude plugin exec form | the quoted executable with `args: []` fails before entering the hook; the unquoted correction passes disposable direct-exec probes for plain paths, spaces and literal shell metacharacters; the asset matches original-owner commit `ca9bcf67ddc771368f9d44052a2bdbc775a71ec8` exactly |
| plugin generation and rollback | changing only `hooks.json` changes the independently verified ten-file digest; both generations pass admission and changed content under the old digest fails; real runtime-file installation makes the stable plugin link follow current; failed stop retains the candidate, and successful restore selects the prior ten files/plugin/launcher/unit with prior receipts intact, using only supervisor/health stand-ins |
| corrected skid generation | staged ten-file identity matches an independent encoding/hash; config/launcher/shell/plugin assets match the owner templates; source closures no longer include private-home provisioning or codex hook assets |
| herdr declarations | macos/arch/devbox service validation passes without provider-home overrides and with an unrelated gateway port; the gate admits the existing normal selectors and rejects the withdrawn private selectors |
| native helper | actual pinned frozen installation and repeat apply passed in a disposable home; final-path entry point and rendered launcher returned the expected invalid-request envelope; exact shim bytes/mode, selected native command/disposable home, quoted environment paths and missing-native/missing-shim refusal passed; these checks establish dispatch, not account behavior |
| cognition declarations | eight operational inputs below remain byte-identical to baseline; this is source evidence, not live continuity acceptance |

unchanged cognition inputs: `assets/codex/{profiles.json,codex-shared.py,
codex-shared@.service,codex-shared.tmpfiles}`, `assets/dotfiles/zshenv`,
`ansible/playbooks/tasks/{codex-runtime-preflight.yml,codex-runtime-activate.yml}`,
and `ansible/roles/codex_shared/tasks/main.yml`.

the source checks found and repaired inherited or split-exposed defects:
gateway signing validation, old-name archive ordering, hyphenated receipt
rejection, separate receipt writes authorizing a mixed pair, recovery producing
duplicate pointers, generation admission omitting directory mode/digest suffix,
silent remote exit 2 being reported as success, and devbox ingress writes
running as the unprivileged gateway user. the coordinating operator reported
that final privilege defect during live apply; the correction places only
ingress under the existing deployment principal's root authority. a later
native claude probe exposed literal shell quotes in an exec-form hook command;
the corrected asset changes its generation identity without changing the
published gateway archive pin. helper
environments are built at their final immutable paths; moving a built python
environment would leave broken entry-point paths.

## limits and decisions

both published host pins are recorded and their artifacts verified in
temporary directories.
no live service, provider account, tmux session, phone,
repository namespace or credential was changed by this source work. the devbox
codex feature observation used only a disposable empty home.

live supervisor behavior, authenticated provider hooks/control, worker and
attachment continuity, existing-account history/hook coexistence, tailnet reachability and phone
acceptance are `NOT_RUN`. the [runbook](gateway-separation-runbook.md) names
their owners, sequence and evidence requirements; the
[open issue](issues/gateway-separation.md) tracks remaining cutover qualification.

the implementation retains the existing artifact/runtime/unit machinery,
shared through two explicit product owners. one atomic pair makes recovery
authoritative while retaining the published informational receipt names.
both products retain existing provider accounts, native integrations and
jarvis's worker map. gateway replacement preserves the supervised herdr runtime,
workers and snapshot. skid-owned shell setup adds guarded bash/zsh sources;
ordinary unmarked and genuine herdr shells do not load skid functions. the
managed zsh template retains one inert guard so ordinary dotfile reinstallation
cannot erase skid support; no extension framework or once-per-shell flag is
introduced. shared account settings/history remain visible across products.
gateway maintenance requires already installed shared host tools and never upgrades
them. helper/plugin rollback and the original app's implemented fleet verifier
use the agreed ten-file generation contract.
separately pinned helper environments remain on disk, preserving all retained
generation dependencies without adding collection machinery.

restoring the established codex launcher also retains its existing coupling to
the shared-daemon helper. that limitation is recorded again in
[wrapper/daemon coupling](issues/codex-wrapper-daemon-coupling.md); changing the
launcher architecture is outside this behavior-preserving correction.
