# Lean convergence specification

Status: implementation contract. Hard cutover. No compatibility period.

## 1. Outcome

`dev-server` is a one-user host converger. It MUST:

1. install or update declared packages and files;
2. emit typed changes only for durable mutations;
3. activate only consumers affected by those changes;
4. prove a small set of critical postconditions;
5. report changes, deferrals, and required user actions tersely.

```text
declared state -> reconcile -> changes -> activation -> postconditions -> summary
```

With unchanged declared inputs and fixed native package candidates, an identical second apply MUST perform no managed-state mutation, open no ingress, and restart/reload nothing. Native repository metadata/cache refresh is not managed state.

## 2. Scope

In scope:

- macOS and exact-host Arch workstation packages, dotfiles, AI tools, and host configuration;
- create-if-missing Hetzner devbox provisioning and steady-state Ubuntu convergence;
- installation and activation of one pinned Skíðblaðnir release per host;
- explicit service lifecycle, enrollment prompts, deferred-action reporting, tests, and CI.

Owned elsewhere:

- Skíðblaðnir invitation, fleet operation, acceptance, lifetime, reboot, and outage workflows;
- Skíðblaðnir release certification and cross-artifact Android validation;
- isolation for unattended unsafe agents. Until Skíðblaðnir supplies it, unsafe permission modes are unavailable.

Trade-off: the upstream handoff adds one cross-repository dependency, and safe agent defaults reduce unattended autonomy; both remove product/security policy from a host installer.

## 3. Goals

- One explicit operation per blast radius: `workstation apply`, `devbox apply`.
- Declared, reviewable update policy; no mutable remote code execution.
- Native package managers and Ansible remain authoritative.
- One shared atomic file-install primitive and one closed activation registry.
- Critical identity, credentials, network boundaries, and the prior healthy Skíðblaðnir runtime survive every failure.
- A concise action summary replaces positive-health output.
- Delete duplicate, dead, diagnostic, acceptance, and legacy paths.

## 4. Non-goals

- Multi-user or generic host configuration.
- A profile/plugin framework, interactive setup wizard, or modes such as minimal/full/repair/force.
- Generic process discovery or automatic restart of arbitrary user work.
- A standalone doctor, drift mirror, monitoring system, dashboard, or machine-readable public API.
- Automatic package removal, VPS recreation/deletion, reboot, tmux termination, or interruption of running containers.
- Nix/Home Manager, OpenTofu, a new package manager, SBOM/SLSA infrastructure, or cross-platform abstraction beyond the three owned hosts.
- Backward-compatible commands, aliases, layouts, schemas, state readers, or fallbacks.

Trade-off: deferring Nix, OpenTofu, signing infrastructure, and generic automation leaves some native-platform variation and manual state; it avoids four new control planes for three fixed hosts.

## 5. Public API

```text
./workstation apply
./workstation {help|--help|-h}
./devbox apply
./devbox {help|--help|-h}
./test
```

Rules:

- The operation is explicit. An omitted operation MUST show help and exit `64`; it MUST NOT imply `apply`.
- `converge`, `doctor`, and the repository-level `skidbladnir` command are removed, not aliased.
- Exit `0`: declared durable state is installed; any intentionally deferred activation is reported.
- Exit `2`: a user enrollment/action is required; no unsafe workaround was taken; rerun is safe.
- Exit `64`: invalid invocation. Exit `1`: operational or invariant failure.
- Orchestrator result lines use only: `INSTALLED`, `UPDATED`, `CHANGED`, `STARTED`, `RELOADED`, `RESTARTED`, `DEFERRED`, `ACTION`, `UP TO DATE`, `ERROR`. Native tool diagnostics may pass through unchanged.
- Output lists mutations/actions only, followed by one summary. No `PASS` wall, spinner, prompt, or decorative UI.
- Canonical user-facing host names are `macbook`, `arch`, and `devbox`. Existing provider resource IDs may remain non-user-facing to avoid identity churn.

Trade-off: two commands remain instead of one target flag; their distinct local/cloud blast radii stay visible.

## 6. Apply lifecycle

Each target orchestrator owns this order:

1. **Preflight:** platform/host gate, required local tools, credentials, schemas, network reachability. Read-only.
2. **Resolve:** validate repository declarations, fingerprint file bytes and
   modes, copy the declared controller closure to a private per-run stage, verify
   the copy, and consume only that immutable stage. Native package candidates
   remain package-manager observations.
3. **Reconcile:** native package operations and compare-before-write file installation.
4. **Activate:** deduplicated, explicit consumer actions. Never infer consumers from the process table.
5. **Verify:** bounded functional/security postconditions.
6. **Summarize:** stable action vocabulary and exit status.

Failure rules:

- Fail closed before mutation when an input, platform, host, artifact, or credential is invalid.
- Native package-manager partial completion is repaired by rerunning its native reconciler; do not build a package rollback layer.
- Critical services MUST compare desired activation identity with observed/recorded active identity, not only current-run file changes. This closes interruption windows.
- Prefer live state (service version/health). If live state cannot prove startup-read configuration, store one atomic active-input SHA at `~/.local/state/dev-server/active/<consumer>.sha256` and update it only after successful activation and verification. The root-owned SSH daemon exception is `/var/lib/dev-server/active/ssh.sha256`. Each is a regular non-symlink mode-`0600` file containing exactly 64 lowercase hex characters plus newline; a principal MUST NOT own the activation proof for a more-privileged consumer.
- Noncritical live-session convenience, such as sourcing tmux config, occurs
  beside its owning subsystem. Tmux records the loaded config SHA in a live
  server option, not a durable journal, so retry detects an interrupted reload.
- Temporary files are created beside their target or on the same filesystem and removed on every exit path.

## 7. Shared capability contract

`lib/common.sh` is the only shared shell foundation. It owns:

- `log`, `warn`, `die`, `require_cmd`;
- portable file/stream SHA-256;
- atomic compare/install: regular non-symlink source and target, desired mode, same-directory staging, byte/mode verification, atomic rename;
- a deduplicated set of closed change identifiers;
- stable result rendering and exit semantics.

It MUST NOT own platform policy, service names, package lists, JSON schemas, retries, or a generic workflow engine.

Change identifier grammar is `^[a-z][a-z0-9]*(\.[a-z][a-z0-9_]*)+$`. Identifiers are constants, never derived from external text. Adding one requires a registry entry and lifecycle test.

Closed registry:

| Change | Consumer action |
|---|---|
| `tmux.config` | source a running server once |
| `shell.config` | none; future shells |
| `desktop.session` | defer to next login |
| `ssh.config` | validate, then reload SSH |
| `docker.config` | restart only with no running containers; otherwise defer |
| `skid.unit` | daemon-reload/bootstrap, then activate gateway |
| `skid.runtime` | start or restart gateway once |
| `skid.integration` | none; future agents |
| `tailscale.serve` | reconcile Serve mapping; never restart Tailscale |
| `system.reboot` | report; never reboot |

No universal `restart` helper is permitted. Platform-specific activation remains beside its subsystem.

Trade-off: each new consumer requires one explicit registry decision and test; this prevents unsafe guessed restarts.

## 8. Subsystems

### 8.1 Workstation orchestration

`workstation apply` MUST run: platform gate -> native packages -> dotfiles ->
personal host configuration -> AI tools -> Skíðblaðnir -> postconditions.

- Darwin is `macbook`; Linux is supported only when both Arch and the exact `arch` host gate match.
- Hardware, dracut, systemd-boot, touchpad, and XFCE policy MUST be isolated as exact-host personal policy, not generic Arch behavior.
- No optional mode matrix. An owned host receives its declared state.

Trade-off: host names remain hard-coded. This is safer and smaller than pretending the configuration is reusable.

### 8.2 Packages

- macOS: `brew update` plus `brew bundle`; let Homebrew decide missing/outdated/no-op state.
- Arch: full `pacman -Syu --needed`, then the declared AUR manifest. Partial upgrades are forbidden.
- Ubuntu: Ansible apt cache plus declared packages at the configured repository candidate; unattended security updates remain. Distribution upgrades and automatic reboot are forbidden.
- Delete `packages/arch.remove.txt`. Removal is an explicit operator action outside apply.
- Configure maintenance timers, but do not run reflector, pkgfile, cache cleanup, or `tldr` refresh merely because apply ran.
- Native package/service scripts may perform their supported activation. Repository-managed services still use the closed registry. Other stale services/sessions are named as `DEFERRED` using native advice where available; apply MUST NOT restart an unregistered consumer or kill arbitrary processes.

Trade-off: rolling OS repositories favor freshness over byte-for-byte replay of an old apply.

### 8.3 Files, personal policy, and AI tools

- All managed files use the shared atomic compare/install primitive.
- A file is either fully repo-owned or unchanged. The sole exception is an explicitly named, parser-backed configuration key rewritten atomically; partial `sed`/append/block ownership is forbidden.
- Reload tmux only when its live config SHA differs; never restart the tmux
  server for a binary upgrade.
- Git plugins live in exact commit generations under
  `~/.local/share/dev-server/git-plugins/` and are published through atomic
  links at their conventional paths. In-place legacy clones are rejected, not
  adopted; interrupted candidates are discarded and retried.
- Cursor settings are the sole parser-backed partial-key exception. Validate
  path topology, bounded strict JSON with unique keys, and object shape before
  extension or file mutation; rewrite only `remote.SSH.remotePlatform` through
  same-directory atomic promotion.
- Plain `codex` and `claude` are personal upstream commands. Retain only explicit `codex-work`, `codex-work2`, and `claude-work` wrappers.
- The wrapper dispatches only by its fixed basename; remove cwd/`-C` inference and `*-personal` aliases. Retain isolation tests.
- AI installation MUST NOT depend on a Skíðblaðnir Claude plugin.
- Use native/standard lock formats where available. Pin remote installers, Git plugin commits, and Ansible. `curl | sh`, `curl | bash`, executable `@latest`, and mutable branch execution are forbidden.
- AI CLI updates may be bumped frequently by a reviewable lock-update workflow; apply consumes the lock only.

Trade-off: newest AI releases can lag the channel briefly; installs become reproducible and reversible.

### 8.4 Devbox provisioning and configuration

`devbox apply` has two internal paths, never two public modes:

- **Absent server:** create -> open operator `/32` bootstrap SSH -> cloud-init/Tailscale and deployment principal -> establish host key -> close bootstrap ingress in an exit-safe cleanup -> apply Ansible.
- **Existing server:** tailnet SSH as the deployment principal -> assert steady cloud firewall -> apply Ansible. It MUST never open public SSH or delete known-host entries.

Additional rules:

- Hetzner firewall and UFW remain separate enforced boundaries. Steady state has no public 22/80/443 rule.
- Existing-server preflight may repair only the exact steady Hetzner firewall
  attachment/rules before proving tailnet reachability. This single safety
  exception closes interrupted bootstrap ingress and cannot create a server,
  public rule, credential, or other host state.
- If UFW is inactive, reset its hidden persisted store and rebuild the exact
  deny-incoming/tailnet-only boundary before enabling it.
- Host keys are reset only for a newly created/replaced server.
- Hetzner and tailnet observations are authoritative. Remove executable `secrets/devbox-state.env`; bootstrap IP/CIDR values are ephemeral, and steady SSH resolves the exact tailnet host. Persist no duplicate cloud lifecycle state.
- GitHub account/key mutation is removed. A missing account enrollment is one `ACTION` with a manual exact command.
- Ansible is authoritative for Ubuntu state and consumes an immutable staged
  controller closure. Tasks MUST report truthful `changed` state and notify
  native handlers; no blanket `changed_when: false`.
- SSH configuration is validated before reload. Rootless Docker's composite
  active identity covers daemon config, Docker package version, and the
  supported setup tool's generated unit. A changed or partial setup is rebuilt
  and API-verified only after an immediate zero-running-container check;
  otherwise it remains unjournaled and `DEFERRED`.
- Remove blanket passwordless sudo from the agent/user account. The operator-only `dev-server-deploy` principal owns Ansible's passwordless elevation and separate SSH key; it owns no workspace, AI, Tailscale, or user credentials and never runs agents.

Trade-off: a separate deployment principal/key adds one credential; it prevents remote agents from inheriting deployment privilege.

### 8.5 Skíðblaðnir installation

Keep a small local installer; product packaging is outside this 80/20 cut. Layout:

```text
~/.local/share/skidbladnir/
  releases/<version>-<artifact-sha256>/
    skidbladnir
    characters.json
    release.json
    host-config.json
  current -> releases/<version>-<artifact-sha256>
  previous -> releases/<prior-generation>       # present only after an upgrade
  units/<unit-sha256>/
    launcher
    unit
  .apply.lock
~/.local/bin/
  skidbladnir -> ../share/skidbladnir/current/skidbladnir
  skidbladnir-launch
~/.config/skidbladnir/
  bearer
  machine-handle
~/.local/state/dev-server/active/
  skid.runtime.sha256
  skid.unit.sha256
```

Rules:

- Release and credential directories are user-private. Bearer and machine handle are regular, non-symlink, mode `0600` files and are never regenerated or replaced when present; invalid state fails closed.
- `current`, `previous`, and `~/.local/bin/skidbladnir` are the only intentional Skíðblaðnir symlinks. Create each as a validated relative temporary symlink and atomically rename it; reject every unexpected symlink in protected paths.
- Under one nonblocking OS lock: download to same-filesystem staging; verify archive SHA, exact three release members, release manifest, executable version/source; add validated host config; rename the complete generation; atomically switch `current`.
- Gateway runtime identity covers binary, catalogue, release manifest, and host
  config. Unit/launcher identity is separate and retains the verified unit
  generation needed for rollback after an interrupted overwrite.
- Start if inactive. Restart once if desired runtime/unit identity differs from active identity. After authenticated health reports the desired version, record active identity.
- On failed activation, atomically restore the prior pointer and restart/verify it. On a failed first installation, leave the service inactive and the candidate unreferenced. Keep one prior generation; remove older exact owned generations only after success.
- Install hooks, notifier, and Claude integration independently with `skid.integration`; they MUST NOT restart the gateway. The explicit Codex work wrappers inject the notifier through Codex's supported per-invocation configuration override. Personal Codex notification remains user-owned because Codex exposes one notifier command.
- Configure only private `/v1` Tailscale Serve through the supported CLI. No Funnel, private LocalAPI credentials, ETag/CAS client, or hostname surgery. A stale mapping produces one exact recovery `ACTION` and exit `2`.
- Default host configs MUST NOT contain `--dangerously-bypass-approvals-and-sandbox`, Claude automatic permission mode, or an equivalent bypass.

Release pin schema (`assets/skidbladnir/release-pin.json`):

```json
{
  "schemaVersion": 1,
  "version": "vMAJOR.MINOR.PATCH",
  "sourceSha": "40 lowercase hex",
  "artifacts": {
    "darwin-arm64": { "url": "https URL", "sha256": "64 lowercase hex" },
    "linux-amd64": { "url": "https URL", "sha256": "64 lowercase hex" }
  }
}
```

Admit one JSON value no larger than 4 KiB, with no duplicate object keys and with exact keys/types, exact Skíðblaðnir GitHub release URL/version/asset paths, supported platforms, canonical version, and digests. Android/certificate/checksum-asset proofs are upstream release-CI concerns. Repository review is the trust root; signed provenance is deferred.

Trade-off: repository compromise can replace both URL and digest. Signing would add a second trust system and is outside this cut.

### 8.6 Postconditions

Package-manager success proves package state; do not enumerate packages again. Apply additionally proves only:

- touched managed service is enabled/active after required activation;
- Skíðblaðnir authenticated loopback health reports desired version;
- bearer/machine-handle modes and preservation;
- Tailscale Serve owns only the desired private `/v1` mapping;
- devbox public bootstrap ingress is absent;
- pending reboot/login/container/tmux activation is reported.

No separate code path may reimplement these checks as a doctor.

Trade-off: broad ad hoc diagnosis disappears; apply errors, the small postconditions, and native status commands become the only truthful sources.

### 8.7 Maintainer update workflow

Updating desired state is not a public app command:

1. bump standard tool locks with their native command;
2. replace the Skíðblaðnir pin only from its published release manifest;
3. run `./test`, review the version/digest diff, and commit it;
4. run `apply` separately on each desired host.

CI validates but never writes locks, merges, or deploys. Automation may open a future pull request only after manual cadence becomes an observed burden.

Trade-off: AI/tool lock updates are manual in this cut; this avoids a privileged dependency bot and another update implementation.

### 8.8 Test workflow

`ci.yml` runs tracked-file static/schema checks and hermetic contract tests on Ubuntu and macOS without repository secrets or live cloud/package mutation. Platform commands are fakes with recorded actions; the owned Arch host remains the only live Arch acceptance target.

Trade-off: CI does not perform a destructive real-host apply. Failure injection and the final local Arch apply cover the lifecycle without creating a disposable fleet.

Arch live acceptance MUST use an attached operator terminal and normal sudo
authentication. Do not grant the user/agent account blanket passwordless
elevation to make automation unattended.

## 9. Files

Delete:

- `skidbladnir`
- `lib/doctor.sh`
- `lib/skidbladnir-invite.sh`
- `lib/skidbladnir-operator.sh`
- `packages/arch.remove.txt`
- executable `secrets/devbox-state.env` state handling
- `ansible/playbooks/converge.yml` and every production `converge` symbol; replace them with `apply.yml`/`apply`
- legacy Skíðblaðnir journal/activation/doctor/operator code and tests
- hidden-path AI routing and personal aliases
- dead `canonical_path`, `resolve_path`, and unused doctor helpers

Keep and reduce:

- `workstation`, `devbox`, `test`
- `lib/common.sh`, package, dotfile, AI, remote-devbox, and Skíðblaðnir libraries
- native manifests, Ansible roles/handlers, cloud-init, desired assets

Add:

- `lib/personal-arch.sh` for exact-host desktop/hardware policy
- `assets/routers/ai-profile` for explicit work wrappers
- `tests/helpers.sh`, `tests/packages.sh`, `tests/devbox.sh`
- `.github/workflows/ci.yml`

Do not create a framework directory, schema package, generated-code layer, or docs hierarchy.

## 10. Hard cutover

- Remove old CLI commands and code in the same release that introduces `apply`.
- Do not read old transaction markers, release layout, command names, release-pin schema, or state formats.
- Before the first new apply on each host, use one explicit operator runbook to stop Skíðblaðnir; remove the old regular binary, flat catalogue/manifest/archive/host-config, `.release-transaction`, and `.release-activation-required`; and remove old devbox shell state. Never glob. Preserve `bearer`, `machine-handle`, integrations, AI credentials, Docker data, SSH identity, and Tailscale identity.
- Run the new apply, verify health/private exposure, then remove the runbook. No migration logic remains in runtime code.

Trade-off: one brief manual cutover per host and no rollback to the legacy layout. This is the cost of eliminating permanent compatibility machinery; rollback between new immutable generations remains required.

## 11. Non-overlapping work packages

| Work | Exclusive files | Depends on | Done when |
|---|---|---|---|
| A. Shared contract/QA | `lib/common.sh`, `test`, `tests/helpers.sh`, `.github/workflows/ci.yml` | none | atomic install/change/output contracts and tracked-file discovery pass |
| B. Packages/personal host | `lib/packages-*.sh`, `lib/personal-arch.sh`, `packages/*`, Arch hardware/system assets, `tests/packages.sh` | A | native update policy is idempotent; no removal/maintenance one-shots |
| C. Dotfiles/AI | `lib/dotfiles.sh`, `lib/ai-tools.sh`, dotfile/router assets, AI locks, `tests/dotfiles.sh`, `tests/ai-router.sh` | A | compare-write, conditional tmux reload, explicit account isolation, pinned installs |
| D. Skíðblaðnir | `lib/skidbladnir.sh`, Skíðblaðnir assets/pin, `tests/skidbladnir.sh`; delete root/operator/invite files | A, G | generation install, exact activation, rollback, identity preservation, private Serve |
| E. Devbox/Ansible | `devbox`, `lib/remote-devbox.sh`, cloud-init, `ansible/**`, `tests/devbox.sh` | A, D contract | absent/existing firewall paths, truthful handlers, bounded postconditions |
| F. Workstation/API/docs | `workstation`, `README.md`, `tests/platform-skips.sh` | B, C, D | hard-cut public API, target integration, and user journey match this spec |
| G. Upstream Skíðblaðnir | external product repo only | none | operator/release acceptance/invitation exists upstream before local deletion lands |

Packages B and C may run in parallel after A; D may join once G has published the upstream operator boundary. E and F integrate only published subsystem contracts. No package shares a file owner.

## 12. Acceptance criteria

1. Fresh workstation/devbox apply installs desired state and starts required services.
2. With fixed package candidates, immediate second apply emits `UP TO DATE`, makes no managed-state change, opens no ingress, and performs no activation; native metadata/cache refresh is allowed.
3. Each registry change activates exactly its declared consumer once; unrelated changes do not.
4. Existing devbox apply never creates a public firewall rule. New-host success and injected failure both remove bootstrap ingress.
5. Artifact/schema/checksum/member/version failure leaves the current Skíðblaðnir generation and credentials untouched.
6. Interrupted or failed Skíðblaðnir activation converges to the desired healthy generation or verified prior generation on retry.
7. Busy Docker, tmux binary, desktop-session, and reboot-required changes are reported, never forced.
8. Unsupported platform/host, symlinked protected path, invalid secret, or public Serve state fails closed.
9. Static checks discover all tracked shell, JSON, YAML, and plist files; Ansible syntax and contract tests run in CI.
10. Production executable/configuration paths contain no doctor or `converge` symbol, legacy command alias, unsafe agent bypass, private Tailscale LocalAPI, executable `@latest`, pipe-to-shell installer, or automatic Arch removal. Documentation and negative tests may name forbidden behavior.
11. README documents only the two apply journeys, prerequisites, actions, and cutover boundary.

## 13. Implementation rule

When a proposed abstraction does not delete at least two real duplicated implementations or enforce a named invariant, do not add it. When simplification would remove checksum, atomicity, credential preservation, host-key continuity, private ingress, or bounded functional verification, reject the simplification.
