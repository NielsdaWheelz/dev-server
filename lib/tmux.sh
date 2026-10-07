#!/usr/bin/env bash

# 0: live, including zero sessions; 1: absent; 2: observation failed.
tmux_server_present() {
  local observation status
  local LC_ALL=C

  if observation="$(tmux -N display-message -p '#{pid}' 2>&1)"; then
    [[ "$observation" =~ ^[1-9][0-9]*$ ]] || return 2
    return 0
  else
    status=$?
  fi
  if ((status == 1)); then
    case "$observation" in
    'no server running on '* | 'error connecting to '*' (No such file or directory)') return 1 ;;
    esac
  fi
  return 2
}

tmux_report_binary_activation() {
  local client_version server_version status
  local LC_ALL=C

  client_version="$(tmux -V 2>/dev/null)" ||
    die "could not resolve installed tmux version"
  [[ "$client_version" =~ ^tmux\ [!-~]{1,60}$ ]] ||
    die "installed tmux version is invalid"
  if tmux_server_present; then
    server_version="$(tmux -N display-message -p '#{version}' 2>/dev/null)" || {
      render_result DEFERRED tmux \
        "running server version could not be observed; restart it manually"
      return 0
    }
    if [[ "$server_version" != "${client_version#tmux }" ]]; then
      render_result DEFERRED tmux \
        "running sessions keep the prior server until manually restarted"
    fi
    return 0
  else
    status=$?
  fi
  if ((status != 1)); then
    render_result DEFERRED tmux \
      "server state could not be observed; restart it manually"
    return 0
  fi
}

tmux_reload_if_changed() {
  local home desired_sha observed_sha status retired

  command -v tmux >/dev/null 2>&1 || return 0
  if tmux_server_present; then
    status=0
  else
    status=$?
  fi
  ((status == 0)) || {
    ((status == 1)) && return 0
    die 'could not observe tmux server state'
  }

  home="$(dev_server_home)"
  desired_sha="$(dev_server_sha256 "$home/.tmux.conf")" || return 1
  observed_sha="$(tmux -N show-options -gqv @dev-server-config-sha)" ||
    die 'could not observe the running tmux config identity'
  if [[ -n "$observed_sha" ]]; then
    [[ "$observed_sha" =~ ^[0-9a-f]{64}$ ]] ||
      die 'running tmux config identity is invalid'
  fi

  # Stop delayed legacy restores before removing their entry points. Admit only
  # complete native commands naming exact owned aliases or immutable generations.
  retired="$(python3 - "$home" <<'PY'
import re
import shlex
import subprocess
import sys

home = re.escape(sys.argv[1])
resurrect = re.compile(home + r"/(?:\.tmux/plugins/tmux-resurrect|\.local/share/dev-server/git-plugins/tmux-resurrect/[0-9a-f]{40})/scripts/(?:save|restore)\.sh")
tpm = re.compile(home + r"/(?:\.tmux/plugins/tpm|\.local/share/dev-server/git-plugins/tpm/[0-9a-f]{40})/bindings/(?:install|update|clean)_plugins")
changed = 0
for option in ("@resurrect-save-script-path", "@resurrect-restore-script-path"):
    value = subprocess.check_output(["tmux", "-N", "show-options", "-gqv", option], text=True).removesuffix("\n")
    if resurrect.fullmatch(value):
        subprocess.run(["tmux", "-N", "set-option", "-gqu", option], check=True)
        changed += 1
if subprocess.check_output(["tmux", "-N", "show-options", "-gq", "@continuum-restore"], text=True):
    subprocess.run(["tmux", "-N", "set-option", "-gqu", "@continuum-restore"], check=True)
    changed += 1
bindings = subprocess.check_output(["tmux", "-N", "list-keys"], text=True)
for line in bindings.splitlines():
    argv = shlex.split(line)
    if argv[:2] == ["bind-key", "-r"]:
        del argv[1]
    if len(argv) < 6 or argv[:2] != ["bind-key", "-T"]:
        continue
    command = argv[4:]
    if command[:2] == ["run-shell", "-b"]:
        del command[1]
    if (len(command) == 2 and command[0] == "run-shell" and
            (resurrect.fullmatch(command[1]) or tpm.fullmatch(command[1]))):
        subprocess.run(["tmux", "-N", "unbind-key", "-T", argv[2], argv[3]], check=True)
        changed += 1
print(changed)
PY
  )" || die 'could not retire owned tmux plugin controls'
  if [[ "$observed_sha" == "$desired_sha" ]]; then
    ((retired == 0)) || render_result CHANGED tmux 'retired plugin controls'
    return 0
  fi
  tmux -N source-file "$home/.tmux.conf" ||
    die 'could not reload tmux configuration'
  tmux -N set-option -gq @dev-server-config-sha "$desired_sha" ||
    die 'could not record the running tmux config identity'
  render_result RELOADED tmux
}
