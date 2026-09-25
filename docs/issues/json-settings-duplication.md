# preserved json settings repeat the same reader

problem: claude and cursor settings repeat json object reading, regular-file
and size checks, duplicate-key/constant rejection, empty-file handling and
serialization. their actual owned-key mutations are much smaller.

impact: identical format-preservation behavior has multiple maintenance owners.

evidence (2026-09-25): compare `ai_claude_settings` in `lib/ai-tools.sh:295`
with `personal_arch_install_cursor_settings` in `lib/personal-arch.sh:374`.
common also has a strict json reader for declarations with different limits.

follow-up: share the repeated object i/o if a small python utility removes more
complexity than it introduces. keep claude/cursor key edits explicit; do not
add a patch language, product schema registry or general config framework.

resolved when: one implementation preserves unrelated settings for both users,
rejects malformed input before writes, and leaves unchanged output untouched.
