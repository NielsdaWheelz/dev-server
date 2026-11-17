# native memory orientation rollout

status: source adoption verified locally; installed rollout and fresh-session
behavior not run for this change.

problem: installed managed instructions make retrieval conditional on the agent
already recognizing a need for history. fresh sessions can therefore miss prior
preferences and decisions before beginning work.

source owner: `assets/memory/instruction.md`, an exact snapshot of the shared
library's `NATIVE_ORIENTATION_GUIDANCE`. `lib/ai-tools.sh:ai_install_instructions`
distributes it through the existing macbook, arch and devbox apply paths to all
six connected codex/claude personal/work/work2 profiles. jarvis's
`docs/universal-memory.md#orientation-lifecycle-and-outages` owns lifecycle,
coverage, note and outage semantics. capture and shared-tree merges stay host-owned.

source verification, 2026-11-17: the 4,055-byte asset matches the export plus
terminal newline from universal-memory
`a788c885d5529227de55a9da9d8aa940da00eaba`, evaluated from that git object without
importing dependencies. asset sha-256:
`42f0b45730789e2d2af2a6de694e1a5805ef3b70093524cea43e65c664fba0de`.
a temporary integration probe exercised the real instruction installer in
isolated account homes: all six connected, each connected individually, all
disconnected and absent client configuration. exact bytes, mode `0600`, unchanged
inodes/mtimes on reapply, removal of disconnected guidance and preservation of
unrelated account files passed. all three host declarations contain the six
intended native profiles. shell syntax and diff checks passed. the probe and its
fixtures were removed; no retained test suite was added.

independent review confirmed the shared lifecycle and six-profile distribution.
it found missing explicit note retry instructions in the upstream guidance; the
adopted revision includes the correction: caller-supplied saves reuse one
submission id and identical arguments, while host-bound saves retain host-owned
identity and recovery.

evidence, 2026-11-17: read-only macbook inspection found the old conditional
instruction in all six account instruction files, each mode `0600` and sha-256
`8593176fa23ab0a5b253a2f87822fa3becea641596e0a247f2a1da432eac0192`.
all six native configurations register `jarvis-memory`; claude-personal uses
`~/.claude.json`, while work/work2 use their own account roots. these observations
establish configuration only, not that an existing session loaded it.

| boundary | evidence for this change |
| --- | --- |
| source snapshot and six-profile rendering | exact upstream bytes and isolated installer checks passed |
| macbook installation | old conditional instruction observed in all six homes |
| devbox and arch installation | not run |
| fresh-session orientation, compaction and child behavior | not run |
| actual recall usefulness | not evaluated |

rollout retains the existing stopped jarvis/contained-host publication boundary:
atomic replacement invalidates the contained host's file masks. restart and
qualify that same-release host before cognition resumes.

resolved when: normal host apply installs the verified snapshot into every
intended connected profile; fresh sessions demonstrate complete frozen-view
pagination before substantive work, relevant zoom/open/search and receipt-backed
useful notes. verify inherited orientation, missing orientation after compaction,
granted and ungranted children, stale cursors and explicit outages without new
grants or client-owned tree merges. record each host/profile's actual outcome and
any remaining deferral; installed bytes alone do not prove agent behavior. reuse
the [existing activation record](universal-memory-activation.md) for outstanding
host/account access rather than treating its earlier qualification as proof of
this instruction change.
