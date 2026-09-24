# workstation codex-shared retirement

problem: macbook and arch no longer run shared codex app servers, but the
services installed by earlier applies remain until drained: on macbook the
`dev.niels.codex-shared.{personal,work,work2}` launchagents; on arch the
`codex-shared@{personal,work,work2}` user units; on both
`~/.local/libexec/codex-shared`, `~/.config/codex-shared/`,
`~/.local/run/codex-shared/`, `~/.local/share/codex-shared/`, the
`~/.local/state/dev-server/active/codex.runtime.sha256` record, and each account's
`app-server-control/app-server-control.sock` discovery link.

impact: none functionally; the servers keep running and serve any interactive
codex attached to them. stopping them cuts those sessions, so removal waits for
the owner to close them.

remove, per host, once no interactive codex is attached (`lsof -U` shows no
client of the daemon sockets):

```sh
# macbook
for p in personal work work2; do
  launchctl bootout "gui/$(id -u)/dev.niels.codex-shared.$p"
  rm ~/Library/LaunchAgents/dev.niels.codex-shared.$p.plist
done
# arch
for p in personal work work2; do
  systemctl --user disable --now "codex-shared@$p.service"
  rm ~/.config/systemd/user/codex-shared@$p.service
done
systemctl --user daemon-reload
# both
for a in .codex .codex-work .codex-work2; do
  rm -f ~/$a/app-server-control/app-server-control.sock
done
rm -R ~/.local/libexec/codex-shared ~/.config/codex-shared ~/.local/run/codex-shared \
  ~/.local/share/codex-shared
rm ~/.local/state/dev-server/active/codex.runtime.sha256
```

resolved when: neither host lists a codex-shared job or unit, the paths above
are absent, and a fresh interactive `codex` starts embedded.
