# existing macbook codex clients inherited no-colour mode

problem: the 2026-10-09 manual tmux restart inherited `NO_COLOR=1` from the
automation controller. the server passed it to restored terminals and their
subsequently launched codex clients.

impact: those clients suppress colour despite `TERM=tmux-256color`,
`COLORTERM=truecolor`, and the attached tmux client's rgb support.

evidence: the macbook server environment and all eight codex clients in panes
`%2` through `%9` contained `NO_COLOR=1`. arch and devbox had no such server
setting. this was introduced by the maintenance command, not a repository
colour policy.

recovery applied: `tmux -N set-environment -g -u NO_COLOR` removed the setting
from macbook's running server. a new tmux child process verified its absence.
no pane, codex client, daemon, or tmux server was restarted for this correction.

remaining recovery: existing processes retain their inherited environment.
when an affected client can be closed, return to its shell, run `unset NO_COLOR`,
then resume the same conversation with its existing account command. new panes
already receive the corrected server environment. future automated server
starts must clear the controller's `NO_COLOR` before invoking tmux.

resolved when affected clients have been relaunched without `NO_COLOR` and
colour rendering is confirmed. delete this incident record then.
