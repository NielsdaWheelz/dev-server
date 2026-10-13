# unclassified macbook gateway-owned tmux child exit

problem: a recorded tmux child exited during the codex maintenance rollout.
the strict all-process comparison failed; its exact role and exit cause are
unknown. do not describe it as an expected reconnect or complete client
preservation.

impact: native provider, gateway and tmux-server identities survived. account
fingerprints, daemon selections and gateway/configuration records matched.
the observation limits the broader process-preservation claim.

evidence: 2026-10-13, maintenance source `3da3cdb`. missing pid `39978`, started
`11:48:18`, executable `/opt/homebrew/bin/tmux`, parent `63463`. that gateway
retained its pid/start/executable; tmux server `72423` also survived. maintenance
invoked no tmux command, gateway activation or terminating signal. deployed
helper revision `111c91b4` can close owned attachment children when request/pty
work ends; this is a possible mechanism, not attribution of this exit.

resolved when: evidence identifies the child's role and an intended request
ending, or identifies a lifecycle defect that is corrected at its owner. retain
the failed comparison in the dated acceptance; do not recreate a pid or restore
state to manufacture preservation.
