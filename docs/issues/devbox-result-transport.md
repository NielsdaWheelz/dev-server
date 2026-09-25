# devbox translates action messages through several representations

problem: `ansible/roles/skidbladnir/tasks/main.yml:18-38,76-96` recognizes
human action sentences and converts them to custom codes. `devbox:838-890`
converts codes back to prose or scrapes quoted ansible debug output.

impact: a wording change can turn a valid manual action into a failure;
reporting knows subsystem-specific messages at several layers.

evidence (2026-09-24): the role rejects an exit-2 result with no recognized
sentence. the controller matches tailscale codes and reconstructs the same
messages, while herdr lines are extracted from `"msg": "ACTION ..."` text.

follow-up: carry the subsystem's exit status and result lines through one
structured ansible reporting path, then render once. preserve exit 2,
herdr-before-skid ordering, true failures, and recovery instructions. this
needs a small transport contract, not a generic workflow engine.

resolved when: changing explanatory wording requires one edit and tests show
actions, failures, and deferrals survive transport without prose matching or
dependence on ansible's human display format.
