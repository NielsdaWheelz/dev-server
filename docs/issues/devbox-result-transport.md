# devbox translates action messages through several representations

problem: `ansible/roles/herdr/tasks/main.yml` recognizes human action sentences
and converts them to custom codes. `devbox` scrapes quoted ansible debug output.
the dedicated gateway playbook carries result lines without the former
tailscale-specific codes, but its controller still parses that display format.

impact: a wording change can turn a valid manual action into a failure;
reporting knows subsystem-specific messages at several layers.

evidence (2026-09-24; updated for separation): the herdr role rejects an exit-2
result with no recognized sentence. herdr and gateway result lines are extracted
from `"msg": "ACTION ..."` text. separation removes the old gateway sentence
round-trip but does not replace ansible's human-output transport.

follow-up: carry the subsystem's exit status and result lines through one
structured ansible reporting path, then render once. preserve exit 2,
independent gateway dispatch, true failures, and recovery instructions. this
needs a small transport contract, not a generic workflow engine.

resolved when: changing explanatory wording requires one edit and tests show
actions, failures, and deferrals survive transport without prose matching or
dependence on ansible's human display format.
