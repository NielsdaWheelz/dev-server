# codex account homes still have several owners

problem: `assets/codex/profiles.json` drives wrappers and skid, but
`ai_install_dirs` and `ai_install_instructions` hardcode the old home names.
the herdr gate and `herdr_install_integrations` also hardcode them. workstation home projection is repeated
in `codex-shared.py` and `skidbladnir_render_configs`.

impact: a declaration change can route an account to one home while creating
its directory/instructions elsewhere, and the gate rejects the new home.

evidence (2026-09-25): an in-memory work-home change to `.codex-employer`
changed the generated launcher while installer fixtures still selected
`.codex-work`. references: `lib/ai-tools.sh:54,283`,
`assets/codex/codex-shared.py:210`, `lib/skidbladnir.sh:113`,
`lib/herdr.sh:535`, and `assets/herdr/herdr-gate:37`.

follow-up: resolve the existing declaration once for the host; use its account
paths for directories, instructions, wrappers, integrations and the gate's
environment allowlist. keep the gate's command policy explicit. no new account
registry or generic profile framework.

resolved when: changing one declared account home produces consistent paths
in every consumer, with existing credentials preserved and unrelated gate
commands still refused.
