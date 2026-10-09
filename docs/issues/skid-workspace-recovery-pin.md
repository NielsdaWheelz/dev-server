# pinned skid has no automatic workspace recovery

problem: host apply retires tmux-resurrect and tmux-continuum, but the pinned
skid v0.13.0 predates skid's workspace recovery implementation.

impact: a tmux restart currently needs a manual workspace snapshot and terminal
recreation. provider-owned codex work can survive independently, but terminal
names and directories are not automatically restored by the deployed gateway.

evidence: during 2026-10-09 fleet maintenance, all three gateways used v0.13.0
and none had `~/.local/state/skidbladnir/workspace.json`. the pinned source lacks
`internal/tmux/recovery.go`; upstream main includes recovery in commit `99b9bb2`.
the authorized tmux restarts therefore used temporary snapshots and explicit
fresh-shell restoration through the installed skid terminal helper.

resolution: publish and pin a verified skid release with workspace recovery,
deploy it to the fleet, and prove saved names, directories and presentation
metadata survive an explicitly authorized restart. recovered shells must not
automatically replay provider launches or conversation bindings.
