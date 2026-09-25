#!/usr/bin/env bash

tmux_report_binary_activation() {
  local client_version server_version status
  local LC_ALL=C

  client_version="$(tmux -V 2>/dev/null)" ||
    die "could not resolve installed tmux version"
  [[ "$client_version" =~ ^tmux\ [!-~]{1,60}$ ]] ||
    die "installed tmux version is invalid"
  if tmux list-sessions >/dev/null 2>&1; then
    server_version="$(tmux display-message -p '#{version}' 2>/dev/null)" || {
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
      "session state could not be proven idle; restart it manually"
    return 0
  fi
}

tmux_reload_if_changed() {
  local desired_sha observed_sha status plugin

  command -v tmux >/dev/null 2>&1 || return 0
  if tmux list-sessions >/dev/null 2>&1; then
    status=0
  else
    status=$?
  fi
  ((status == 0)) || {
    ((status == 1)) && return 0
    die 'could not observe tmux session state'
  }

  # Plugin links name immutable, verified commit generations. Include them so
  # a pin change remains pending even if an earlier apply failed during reload.
  desired_sha="$(
    {
      dev_server_sha256 "$(dev_server_home)/.tmux.conf" || exit 1
      for plugin in tmux-resurrect tmux-continuum; do
        readlink "$(dev_server_home)/.tmux/plugins/$plugin" || exit 1
      done
    } | dev_server_sha256_stream
  )" || return 1
  if observed_sha="$(tmux show-options -gv @dev-server-config-sha 2>/dev/null)"; then
    [[ "$observed_sha" =~ ^[0-9a-f]{64}$ ]] ||
      die 'running tmux config identity is invalid'
    [[ "$observed_sha" == "$desired_sha" ]] && return 0
  fi

  tmux source-file "$(dev_server_home)/.tmux.conf" ||
    die 'could not reload tmux configuration'
  # Retire only bindings that still execute the old manager, including custom keys.
  python3 - "$(dev_server_home)/.tmux/plugins/tpm" <<'PY' ||
import shlex
import subprocess
import sys

commands = {f"{sys.argv[1]}/bindings/{action}_plugins" for action in ("install", "update", "clean")}
bindings = subprocess.check_output(["tmux", "list-keys", "-T", "prefix"], text=True)
for line in bindings.splitlines():
    argv = shlex.split(line)
    if (len(argv) == 6 and argv[:3] == ["bind-key", "-T", "prefix"]
            and argv[4] == "run-shell" and argv[5] in commands):
        subprocess.run(["tmux", "unbind-key", "-T", "prefix", argv[3]], check=True)
PY
    die 'could not retire tpm bindings'
  tmux set-option -gq @dev-server-config-sha "$desired_sha" ||
    die 'could not record the running tmux config identity'
  render_result RELOADED tmux
}
