# cognition account homes still have two declarations

problem: `assets/codex/profiles.json` owns cognition account homes, but
`ai_install_dirs` and `ai_install_instructions` still hardcode ordinary account
home names. changing the cognition declaration does not change those host-tool
provisioning paths.

impact: a declaration change can select a cognition home while creating its
directory/instructions elsewhere.

evidence (2026-09-25): an in-memory work-home change to `.codex-employer`
changed the former generated launcher while installer fixtures still selected
`.codex-work`. separation removes interactive wrappers, gateway profiles,
integrations and the gate from this declaration: their private product homes
are an independent fixed contract. the remaining hardcoded ordinary paths
are in `ai_install_dirs` and `ai_install_instructions` in `lib/ai-tools.sh`.

follow-up: use the existing cognition declaration for cognition directory and
instruction provisioning. keep private interactive product homes separate;
do not route workers back into cognition homes to unify unrelated ownership.
no new account registry or generic profile framework.

resolved when: changing one declared cognition account home produces consistent
paths in its consumers, with credentials and interactive product homes preserved.
