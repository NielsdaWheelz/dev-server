# installed workspace recovery awaits restart qualification

problem: v0.14.0 includes workspace recovery and is installed fleet-wide, but
saved workspace restoration through an actual approved restart remains unqualified.

impact: a present checkpoint proves capture, not successful reconstruction of
names, directories and presentation metadata after restart.

evidence: during 2026-10-09 fleet maintenance, all three gateways used v0.13.0
and none had `~/.local/state/skidbladnir/workspace.json`. the pinned source lacks
`internal/tmux/recovery.go`; upstream main includes recovery in commit `99b9bb2`.
the authorized tmux restarts therefore used temporary snapshots and explicit
fresh-shell restoration through the installed skid terminal helper.

later 2026-10-09 release cutover pins and installs v0.14.0 from exact source
`111c91b4c97e70ee154dae3032d011533951f55e` on macbook, devbox and arch. each has
`~/.local/state/skidbladnir/workspace.json`; retired plugin links/configuration
were absent before activation. no restart or reboot was performed during release.

resolution: prove saved names, directories and presentation
metadata survive an explicitly authorized restart. recovered shells must not
automatically replay provider launches or conversation bindings.
