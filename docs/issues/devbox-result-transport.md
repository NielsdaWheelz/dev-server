# devbox translates action messages through several representations

problem: `ansible/playbooks/gateway.yml` reports subsystem result lines through
ansible debug output, and `devbox_gateway` scrapes its quoted human display format.

impact: an ansible display-format change can hide a valid action or mutation
from the controller's result summary.

evidence (2026-09-29): `devbox_gateway` extracts result lines with a
`"msg": "(ACTION|INSTALLED|...) ..."` expression and removes the surrounding
quotes. the playbook's final debug task owns that presentation.

2026-10-17: ordinary host apply had a separate memory-result encoding defect:
literal `\n` separators hid action lines from the controller. yaml now decodes
those separators before ansible templates the json result. six local round trips
through the actual ansible task and controller passed: absent bundle, pending
pin, combined ai/memory actions, ingress action, collector action and success.
quotes and literal backslashes were preserved. full host apply was not rerun;
the gateway callback-format dependency above remains unresolved.

follow-up: the playbook and controller should preserve subsystem status and
result lines independently of ansible's human display. retain exit 2, true
failures and recovery instructions.

resolved when: changing explanatory wording requires one edit and tests show
actions, failures, and deferrals survive transport without prose matching or
dependence on ansible's human display format.
