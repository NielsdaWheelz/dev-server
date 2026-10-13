# claude native maintenance can report unactivated updates as successful

problem: native maintenance loses an activation failure when the old canonical
launcher still works. `update` can report success and exit `0` while the selected
executable remains old. `install`, `--force` and the official shell installer
share the same defective result path.

impact: exit status plus a valid post-update executable cannot distinguish a
failed activation from a legitimate unchanged result. strict normal-apply
maintenance cannot use that interface without a corrected upstream contract.

evidence: a genuine disposable `2.1.288` installation selected stable `2.1.287`.
with only its private command directory made nonwritable (`0555`), `update`
reported success and exited `0`; canonical link, bytes and version remained
`2.1.288`. fixture permissions were restored. released `2.1.296` package review
confirms the activation-failure flag is discarded before the public result.
ordinary network failure separately returned `1`.

reproduce only in a disposable native installation: choose a different available
channel target, make its private `.local/bin` nonwritable, run its canonical
`update` with fixed fixture `HOME`, personal context and closed stdin, then compare
exit status with canonical selection and version. restore permissions afterward.

scope: documented upstream blocker. no bundled-code patch, prose parser,
permission-preflight substitute or duplicate provider policy engine.

resolved when: a released supported interface reports activation failure as
failure, or exposes a selected target and structured outcome that can be verified
while preserving upstream channel, version bounds and legitimate no-op behavior.
