# production disk headroom

open for representative-load verification. on 2026-11-20 utc, the shared
filesystem holding native postgres reached 95% used with 7.96 gib available.
exhaustion can interrupt production writes. the local capacity sampler uses
floors of 10 gib and 100,000 inodes. the short history gives no reliable
exhaustion date.

the owner-approved cleanup removed retired development scratch, selected
worktrees, and reproducible caches. unused image copies were removed after
verifying their registry manifests. the retained source checkouts and
referenced evidence were preserved. postgres accepted connections and nexus
production containers remained healthy in the cleanup checks.

at 07:22:25 utc, the filesystem was 60% used with 63,175,106,560 usable bytes
(58.84 gib) and 8,464,503 available inodes. new heavy development runs on the mac.

use the [capacity runbook](../../README.md#postgresql-disk-capacity) to inspect
the local journal. close after measuring usable bytes and inodes above the
adopted floors under representative production activity. jarvis adr 0088 owns
the monitoring contract.
