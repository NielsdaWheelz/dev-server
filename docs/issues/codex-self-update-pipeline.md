# codex self-update can hide installer download failure

problem: the inspected `0.162.1` native updater runs a shell pipeline without
pipeline failure propagation. a failed installer download can leave the final
shell successful, with the old executable still valid.

impact: updater success and a valid unchanged version cannot prove maintenance
succeeded. normal dev-server apply must use its existing checked download,
syntax validation and official-installer execution path.

evidence: the
[pinned update action](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/tui/src/update_action.rs#L55)
invokes
`sh -c 'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh'`.
a failed first pipeline command followed by an empty successful shell returns
success. the
[cli checks the final child status](https://github.com/openai/codex/blob/rust-v0.162.1/codex-rs/cli/src/main.rs#L849).
the installer itself remains the supported native maintenance interface.

scope: upstream proposal only; no fork or upstream release dependency. local
apply avoids this interface rather than interpreting updater prose.

resolved when: released native self-update returns a nonzero status on installer
download failure and cannot report success for a skipped failed download.
