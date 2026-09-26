# gateway separation source validation

2026-09-25, against dev-server baseline `8498933`. temporary probes were
removed; no test framework or ci workflow was added. fixtures and service
stand-ins establish installer behavior only. live activation is pending.

## checks completed

| check | result and scope |
| --- | --- |
| static checks | bash/zsh syntax, shellcheck, json/plist parsing, herdr gate python syntax, and `git diff --check` passed |
| ansible | ordinary apply and selected gateway playbooks passed syntax checks; disposable callback probe rejects silent exit 2 and accepts exit 2 with an action |
| app config contracts | rendered mac configs passed both source-built validators and the published herdr-mobile binary; the mobile owner separately reports published linux config validation passing on devbox and arch; original skid native linux validation remains pending |
| published mobile pin | documented conversion preserves v0.9.0, source `68a652d7ccbeaaf472ef1c5f3a4ea6949808bca4`, and both host digests; github confirms canonical repository id `1342599607`, immutable release and exact tag commit; downloaded archives pass digest, member and manifest checks, and native mac version/config validation |
| selected commands | invalid input rejected; selected pending pins return action/2 before product-home mutation, regardless of the other gateway's invalid port; absent removal needs no release pin or provider assets |
| ingress | a fake tailscale cli verified selected handler apply/remove while preserving the other port and an unrelated same-port handler; foreign handlers and public exposure on the selected origin refused |
| independent installer lifecycle | each product passed disposable first install, repeat apply, forced failed-upgrade recovery and removal with the other absent |
| coinstalled isolation | both products in one disposable home retained identical opposite-product trees, links, units, receipts/pairs and simulated running state after selected repeat, failed upgrade and removal in both directions |
| receipts and recovery | interrupted promotion restores the atomic verified runtime/unit pair; duplicate previous pointer clears; failed retry of an unpaired first candidate returns to no active runtime |
| generation admission | before the correction, both products admitted mode `0755` and a wrong digest suffix; afterward intact `0700` generations pass and both alterations fail; original skid's actual fleet verifier agrees |
| admitted rollback prior | wrong mode or suffix on `previous` fails installed-generation admission; an intact prior restores current, unit and helper/plugin selection with its verified pair and fleet receipt preserved, using only supervisor/health stand-ins |
| unconfirmed stop | forced activation and stop failure preserved the candidate inputs, prior verified pair and one recovery stage; the other product remained unchanged |
| signing boundary | both product validators ignored and preserved unrelated signing paths, including deliberately invalid signing-file shapes |
| namespace boundary | unmarked legacy skid bearer refused and preserved; receipt names support herdr-mobile while rejecting malformed/path-traversal names |
| shell/account routing | disposable bash/zsh startup and fake providers exercised product defaults, explicit account selection, argument preservation, foreign-context cleanup and genuine herdr-pane guard; managed source insertion is idempotent and preserves user bytes |
| native helper | actual pinned frozen installation and repeat apply passed in a disposable home; final-path entry point and rendered launcher returned the expected invalid-request envelope; exact shim bytes/mode, selected native command/private home, quoted environment paths and missing-native/missing-shim refusal passed |
| fresh codex homes | mac codex 0.157.0 and devbox 0.155.1 report hooks enabled with empty disposable homes; no feature setting or account data copied |
| cognition declarations | eight operational inputs below remain byte-identical to baseline; this is source evidence, not live continuity acceptance |

unchanged cognition inputs: `assets/codex/{profiles.json,codex-shared.py,
codex-shared@.service,codex-shared.tmpfiles}`, `assets/dotfiles/zshenv`,
`ansible/playbooks/tasks/{codex-runtime-preflight.yml,codex-runtime-activate.yml}`,
and `ansible/roles/codex_shared/tasks/main.yml`.

the source checks found and repaired inherited or split-exposed defects:
gateway signing validation, old-name archive ordering, hyphenated receipt
rejection, separate receipt writes authorizing a mixed pair, recovery producing
duplicate pointers, generation admission omitting directory mode/digest suffix,
and silent remote exit 2 being reported as success. helper
environments are built at their final immutable paths; moving a built python
environment would leave broken entry-point paths.

## limits and decisions

herdr-mobile's published host pin is recorded and its artifacts verified in
temporary directories. original skid's published pin remains unavailable.
no live service, provider account, tmux session, phone,
repository namespace or credential was changed by this source work. the devbox
codex feature observation used only a disposable empty home.

live supervisor behavior, authenticated provider hooks/control, worker and
attachment continuity, jarvis's worker-map activation, tailnet reachability and phone
acceptance are `NOT_RUN`. the [runbook](gateway-separation-runbook.md) names
their owners, sequence and evidence requirements; the
[open issue](issues/gateway-separation.md) tracks publication and cutover.

the implementation retains the existing artifact/runtime/unit machinery,
shared through two explicit product owners. one atomic pair makes recovery
authoritative while retaining the published informational receipt names.
private homes require fresh login/trust. shell setup adds guarded bash/zsh
sources; ordinary unmarked shells do not load skid functions. gateway
maintenance requires already installed shared host tools and never upgrades
them. helper/plugin rollback and the original app's implemented fleet verifier
use the agreed ten-file generation contract.
separately pinned helper environments remain on disk, preserving all retained
generation dependencies without adding collection machinery.
