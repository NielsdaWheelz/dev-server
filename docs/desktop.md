# desktop development handoff

## development placement

run heavy development on `macbook` pending the desktop handoff. wait while the
mac is unavailable. the hetzner devbox serves production. existing release
pipelines keep their own placement. the desktop takes this work only after its
skid access and representative integration suite pass.

start a new detached rehearsal on the mac with python 3.11+, git, and the local
docker desktop engine available:

```sh
scripts/rehearse-worktree /path/to/repo REV /private/persistent/new-run \
  --expect result.json -- command arg
```

use a revision reachable from a retained git ref. choose a new directory
under existing private persistent storage. the command
receives its path as `REHEARSAL_EVIDENCE_DIR`. finish promised files there and
close the files before exiting. the command owns fixture teardown, including
ignored outputs, temporary databases, and stopped containers. remove only paths
the check created and keep the observed check exit status. use the managed
mac's docker desktop engine for containers. pass ordinary argv and keep secrets
in private configuration. the receipt includes the command arguments.

read `receipt.json` after the run. it gives the exact commit, command exit or
signal, verified evidence paths and hashes, and checkout disposition. a cleanup
failure exits nonzero even when the check passed. report the two outcomes
separately. before sending a report, use a private locator its intended reader
can reopen and verify. an interrupted run retains the checkout.

retained scratch lives under `~/.local/state/dev-server/rehearsals`, outside the
os's temporary-file cleanup. for recovery after a hard kill, use the printed
scratch and evidence paths.
acquire the exclusive scratch-directory lock and keep it open while inspecting
and removing the checkout:

```sh
python3 -c 'import fcntl, os, subprocess, sys
fd = os.open(sys.argv[1], os.O_RDONLY)
fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
raise SystemExit(subprocess.call([os.environ["SHELL"]], pass_fds=(fd,)))' "$scratch"
```

from that shell reopen and hash the files promised in `receipt.json`,
check git status including ignored files and check reachability of head and its
whole reflog from named refs. inspect `lsof -nP +D "$scratch" +D "$evidence"` for open users
apart from the recovery lock holders. inspect binds in all containers, including
stopped ones, on `docker --context desktop-linux`. include local volumes whose
driver binds a host path. preserve changed files or
unreachable commits first. when the checks are complete and clear, use ordinary
`git worktree remove "$scratch/checkout"` from the original repository and
`rmdir "$scratch"`. leave the evidence directory in place.

existing hetzner scratch may contain local work, live users, or the only copy
of a result. use the read-only inventory and inspect each root before proposing
separate disposal. keep uncertain roots.
