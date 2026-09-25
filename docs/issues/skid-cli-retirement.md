# skid cli retirement residue

problem: the v0.8.0 pin retires the skid cli, its notifier, its codex identity
hook, its claude identity plugin and the per-host peer client files. dev-server
no longer manages their paths, so no apply removes what earlier applies and
skid's `scripts/fleet provision-clients` installed. apply itself replaces each
account home's codex `hooks.json` whose parsed json is skid's rendering, and
ansible removes devbox's `/usr/local/libexec/skidbladnir` and its staged skid
copies. everything below is by hand, once per host.

impact: `skid` now runs the v0.8.0 binary, which prints usage and exits 64.
sessions started before the cutover keep the hooks they loaded: codex reruns
skid's `SessionStart` hook on resume and clear, claude-work the plugin's, and
both calls exit 64 because v0.8.0 has no `agent-hook`. new sessions are clean.
a codex `notify` line naming `skid-notify` runs a missing program once the
notifier goes, so the script below removes those lines before the files go.
a codex `hooks.json` holding skid's hook beside herdr's (herdr installed by
hand before the cutover) is not skid's rendering, so apply leaves skid's hook
in it.

blockers: do this after the owner retires the pre-pin rollback (v0.8.0
accepted on all three hosts), because that apply reinstalls the link,
notifier, plugin and `hooks.json`. remove `/etc/jarvis/agent-client.json` only
after jarvis's herdr-codec release no longer reads or checks it.

on every host, as the owner account (`nnandal` on macbook and arch, `niels` on
devbox), drop the `notify` lines and skid's hook from the three codex homes and
the pre-2026-09-01 `~/.codex-personal`, which on the macbook holds both; a file
that held only skid's hook is removed, herdr's entries stay:

```sh
python3 - <<'PY'
import json
import os

home = os.path.expanduser("~")
notify = f'notify = ["{home}/.local/bin/skid-notify"]'

def write(path, text):
    temporary = path + ".skid-retirement"
    with open(temporary, "w", encoding="utf-8") as stream:
        stream.write(text)
    os.chmod(temporary, os.stat(path).st_mode & 0o777)
    os.replace(temporary, path)
    print("edited", path)

for name in (".codex", ".codex-work", ".codex-work2", ".codex-personal"):
    config, hooks = f"{home}/{name}/config.toml", f"{home}/{name}/hooks.json"
    if os.path.isfile(config):
        with open(config, encoding="utf-8") as stream:
            lines = stream.read().splitlines(keepends=True)
        kept = [line for line in lines if line.rstrip("\n") != notify]
        if kept != lines:
            write(config, "".join(kept))
    if os.path.isfile(hooks):
        with open(hooks, encoding="utf-8") as stream:
            value = json.load(stream)
        events = value.get("hooks", {})
        groups = events.get("SessionStart", [])
        kept = [group for group in groups if not any(
            "skidbladnir agent-hook" in hook.get("command", "") for hook in group.get("hooks", []))]
        if kept == groups:
            continue
        if value.get("description") == "Skíðblaðnir agent identity projection":
            del value["description"]
        if kept:
            events["SessionStart"] = kept
        else:
            del events["SessionStart"]
        if not events and list(value) == ["hooks"]:
            os.remove(hooks)
            print("removed", hooks)
        else:
            write(hooks, json.dumps(value, indent=2, ensure_ascii=False) + "\n")
PY
rm ~/.local/bin/skid ~/.local/bin/skid-notify
rm -R ~/.local/share/skidbladnir/claude-agent-identity
```

then on arch and devbox only (the macbook keeps its copy: `scripts/fleet
invite` reads it):

```sh
rm ~/.config/skidbladnir/client.json
```

and on devbox as `dev-server-deploy`:

```sh
sudo rm /etc/jarvis/agent-client.json
```

evidence: dev-server history. the `skid` link: `skidbladnir_apply`, from 639f1a4
until this change. `skid-notify`, codex `hooks.json` and the plugin:
`skidbladnir_install_integrations` and its predecessors, from e912d4f and
a88acfb until this change (#124 renders the hook from one template, same parsed
json). the `notify` line, written at the top of
`~/.codex-{personal,work,work2}/config.toml`:
`skidbladnir_configure_codex_notify`, e912d4f to 39248fb; the personal home
became `~/.codex` in 39248fb. both `client.json` files and
`/etc/jarvis/agent-client.json`: skid `scripts/fleet provision-clients` through
v0.7.0 (`install_client_config`). v0.8.0 exits 64 on `agent-hook`. the
disposable qualification of this change ran the script above against a
`~/.codex-personal` and a merged `hooks.json`.

resolved when, on every host, these print nothing:

```sh
ls -d ~/.local/bin/skid ~/.local/bin/skid-notify ~/.local/share/skidbladnir/claude-agent-identity 2>/dev/null
grep -ls skid-notify ~/.codex/config.toml ~/.codex-work/config.toml ~/.codex-work2/config.toml ~/.codex-personal/config.toml
grep -ls 'skidbladnir agent-hook' ~/.codex/hooks.json ~/.codex-work/hooks.json ~/.codex-work2/hooks.json ~/.codex-personal/hooks.json
```

and `ls ~/.config/skidbladnir/client.json` fails on arch and devbox and
`sudo ls /etc/jarvis/agent-client.json` fails on devbox. in the same change
that deletes this file, delete the retired-`hooks.json` removal in
`herdr_install_integrations`: with the rollback retired nothing writes skid's
file again.
