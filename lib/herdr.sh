#!/usr/bin/env bash

# lib/herdr.sh owns the pinned herdr server on each host: the artifact cache and
# immutable generations under ~/.local/share/herdr, the managed server config at
# ~/.local/share/herdr/config.toml, the user service unit, and its activation.
#
# herdr_preflight PLATFORM validates the declared inputs, stages the pinned release
# when the running server's inputs changed, and returns 2 after rendering an
# ACTION for residue, an unmanaged socket, launchd environment overrides, or
# changed inputs while the server runs. it promotes nothing.
# herdr_apply PLATFORM stages the artifact and generation, then promotes the
# pointers, config and unit only while the service is absent or inactive, starts
# it, and records the active identity once ping and agent-manifests agree.
#
# staging alone (spec §4.3) on any host, fresh ones included; never through herdr_apply:
#   bash -c 'set -euo pipefail
#     cd DEV_SERVER_CHECKOUT; source lib/common.sh; source lib/herdr.sh
#     platform=macos # or arch | devbox
#     home="$(dev_server_home)"; share="$home/.local/share/herdr"
#     herdr_prepare_directories "$home" "$platform"
#     dev_server_acquire_lock "$share/.apply.lock" 8 herdr
#     stage="$(mktemp -d "$share/.apply.stage.XXXXXX")"
#     read -r version _ url sha256 <<<"$(herdr_release_values "$platform" | tr "\t" " ")"
#     herdr_prepare_artifact "$stage" "$version" "$url" "$sha256" "$share/artifacts/$sha256"
#     dev_server_remove_stage "$share" "$stage"
#     exec 8>&-'
#
# the recipe stages the artifact only; herdr_apply builds the generation from it.

: "${dev_server_install_status:=UP TO DATE}"
herdr_platform=''
herdr_version=''
herdr_url=''
herdr_binary_sha=''
herdr_desired_identity=''
herdr_generation_name=''
herdr_preflight_admitted=0
herdr_enablement_changed=0

herdr_platform_key() {
  case "$1" in
  macos) printf 'darwin-arm64\n' ;;
  arch | devbox) printf 'linux-amd64\n' ;;
  *) die "unsupported herdr platform: $1" ;;
  esac
}

herdr_service_name() {
  case "$herdr_platform" in
  macos) printf 'dev.niels.herdr\n' ;;
  arch | devbox) printf 'herdr.service\n' ;;
  *) return 1 ;;
  esac
}

herdr_unit_source() {
  case "$1" in
  macos) printf '%s/herdr/dev.niels.herdr.plist\n' "$(dev_server_assets_dir)" ;;
  arch | devbox) printf '%s/herdr/herdr.service\n' "$(dev_server_assets_dir)" ;;
  *) return 1 ;;
  esac
}

herdr_unit_target() {
  case "$1" in
  macos) printf '%s/Library/LaunchAgents/dev.niels.herdr.plist\n' "$2" ;;
  arch | devbox) printf '%s/.config/systemd/user/herdr.service\n' "$2" ;;
  *) return 1 ;;
  esac
}

herdr_stop_command() {
  case "$herdr_platform" in
  macos) printf 'launchctl bootout gui/%s/dev.niels.herdr\n' "$(id -u)" ;;
  arch | devbox) printf 'systemctl --user stop herdr.service\n' ;;
  *) return 1 ;;
  esac
}

herdr_release_values() {
  local platform="$1"
  local pin artifact
  artifact="$(herdr_platform_key "$platform")"
  pin="$(dev_server_assets_dir)/herdr/release-pin.json"
  dev_server_strict_json_file "$pin" 4096 || return 1

  python3 - "$pin" "$artifact" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
artifact = sys.argv[2]
assets = {"linux-amd64": "herdr-linux-x86_64", "darwin-arm64": "herdr-macos-aarch64"}
if not isinstance(value, dict) or sorted(value) != [
        "artifacts", "schemaVersion", "sourceSha", "version"]:
    raise SystemExit(1)
version = value["version"]
source = value["sourceSha"]
artifacts = value["artifacts"]
if (type(value["schemaVersion"]) is not int or value["schemaVersion"] != 1 or
        not isinstance(version, str) or
        not re.fullmatch(r"v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})", version) or
        not isinstance(source, str) or not re.fullmatch(r"[0-9a-f]{40}", source) or
        not isinstance(artifacts, dict) or sorted(artifacts) != sorted(assets)):
    raise SystemExit(1)
for name, asset in assets.items():
    item = artifacts[name]
    expected = f"https://github.com/herdrdev/herdr/releases/download/{version}/{asset}"
    if (not isinstance(item, dict) or sorted(item) != ["sha256", "url"] or
            item["url"] != expected or not isinstance(item["sha256"], str) or
            not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])):
        raise SystemExit(1)
print("\t".join((version, source, artifacts[artifact]["url"], artifacts[artifact]["sha256"])))
PY
}

# the managed config is exactly the pinned keys; comments and blank lines are free.
herdr_config_valid() {
  local expected=$'[session]\nresume_agents_on_restore = false\n[update]\nversion_check = false\nmanifest_check = false'
  [[ -f "$1" && ! -L "$1" ]] || return 1
  [[ "$(grep -Ev '^[[:space:]]*(#|$)' "$1")" == "$expected" ]]
}

# prints the unit's environment as NAME=VALUE lines and EXEC=<argv, tab-separated>,
# with systemd %h rendered as HOME, after checking the supervisor policy fields.
herdr_unit_environment() {
  python3 - "$1" "$2" "$3" <<'PY'
import plistlib
import shlex
import sys

platform, path, home = sys.argv[1:]
environment = {}
argv = []
if platform == "macos":
    with open(path, "rb") as stream:
        unit = plistlib.load(stream)
    if (unit.get("Label") != "dev.niels.herdr" or unit.get("RunAtLoad") is not True or
            unit.get("KeepAlive") != {"SuccessfulExit": False} or unit.get("Umask") != 18 or
            unit.get("ExitTimeOut") != 15):
        raise SystemExit(1)
    environment = dict(unit.get("EnvironmentVariables", {}))
    argv = list(unit.get("ProgramArguments", []))
else:
    policy = {}
    unset = set()
    with open(path, "r", encoding="utf-8") as stream:
        for raw in stream:
            line = raw.strip()
            if "=" not in line or line.startswith(("#", "[")):
                continue
            key, value = line.split("=", 1)
            if key == "Environment":
                for item in shlex.split(value):
                    name, assigned = item.split("=", 1)
                    environment[name] = assigned.replace("%h", home)
            elif key == "UnsetEnvironment":
                unset.update(value.split())
            elif key == "ExecStart":
                argv = [part.replace("%h", home) for part in shlex.split(value)]
            elif key in ("PartOf", "Requires", "BindsTo", "Wants"):
                raise SystemExit(1)
            else:
                policy[key] = value
    # inherited session state that would redirect herdr or leak into every pane.
    expected_unset = {"XDG_CONFIG_HOME", "XDG_STATE_HOME", "HERDR_SESSION", "HERDR_ENV", "HERDR_PANE_ID",
                      "HERDR_CLIENT_SOCKET_PATH", "TMUX", "TMUX_PANE", "TMUX_TMPDIR"}
    if (unset != expected_unset or policy.get("Restart") != "on-failure" or policy.get("UMask") != "0022" or
            policy.get("WantedBy") != "default.target" or policy.get("TimeoutStopSec") != "15s"):
        raise SystemExit(1)
for name in sorted(environment):
    if "\n" in name or "\n" in environment[name]:
        raise SystemExit(1)
    print(f"{name}={environment[name]}")
print("EXEC=" + "\t".join(argv))
PY
}

herdr_identity() {
  local binary_sha="$1"
  local config="$2"
  local unit="$3"
  printf 'herdr\0%s\nconfig.toml\0%s\nunit\0%s\n' "$binary_sha" \
    "$(dev_server_sha256 "$config")" "$(dev_server_sha256 "$unit")" |
    dev_server_sha256_stream
}

herdr_validate_declared_inputs() {
  local platform="$1"
  local home="$2"
  local pin_line config unit environment

  require_cmd python3 curl
  pin_line="$(herdr_release_values "$platform")" || die 'herdr release pin is invalid'
  IFS=$'\t' read -r herdr_version _ herdr_url herdr_binary_sha <<<"$pin_line"
  config="$(dev_server_assets_dir)/herdr/config.toml"
  herdr_config_valid "$config" || die 'herdr managed config is invalid'
  unit="$(herdr_unit_source "$platform")"
  [[ -f "$unit" && ! -L "$unit" ]] || die "invalid herdr declared file: $unit"
  environment="$(herdr_unit_environment "$platform" "$unit" "$home")" || die 'herdr unit is invalid'
  # the socket path is the one skid's host config names; identity hooks compare it byte for byte.
  if ! grep -Fqx "HERDR_SOCKET_PATH=$home/.config/herdr/herdr.sock" <<<"$environment" ||
    ! grep -Fqx "HERDR_CONFIG_PATH=$home/.local/share/herdr/config.toml" <<<"$environment" ||
    ! grep -Fqx 'LANG=en_US.UTF-8' <<<"$environment" ||
    ! grep -Fqx "EXEC=$home/.local/share/herdr/current/herdr"$'\t'"server" <<<"$environment" ||
    grep -Eq '^(HERDR_SESSION|HERDR_ENV|HERDR_PANE_ID|HERDR_CLIENT_SOCKET_PATH|XDG_CONFIG_HOME|XDG_STATE_HOME)=' <<<"$environment"; then
    die 'herdr unit environment differs from the managed paths'
  fi
  herdr_desired_identity="$(herdr_identity "$herdr_binary_sha" "$config" "$unit")" ||
    die 'herdr desired identity is invalid'
}

herdr_validate_protected_paths() {
  local home="$1"
  local share="$home/.local/share/herdr"
  local path value

  for path in \
    "$home/.local" \
    "$home/.local/share" \
    "$share" \
    "$share/artifacts" \
    "$share/releases" \
    "$home/.local/state" \
    "$home/.local/state/dev-server" \
    "$home/.local/state/dev-server/active" \
    "$home/.config" \
    "$home/.config/herdr"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -d "$path" && ! -L "$path" ]] || die "protected herdr directory is invalid: $path"
    fi
  done
  if [[ -e "$share/current" || -L "$share/current" ]]; then
    value="$(readlink "$share/current" 2>/dev/null)" || die "protected herdr link is invalid: $share/current"
    [[ "$value" =~ ^releases/v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})-[0-9a-f]{64}$ ]] ||
      die "protected herdr link is invalid: $share/current"
  fi
  if [[ -e "$home/.local/bin/herdr" || -L "$home/.local/bin/herdr" ]]; then
    [[ -L "$home/.local/bin/herdr" && "$(readlink "$home/.local/bin/herdr")" == ../share/herdr/current/herdr ]] ||
      die "protected herdr link is invalid: $home/.local/bin/herdr"
  fi
  if [[ -e "$share/config.toml" || -L "$share/config.toml" ]]; then
    [[ -f "$share/config.toml" && ! -L "$share/config.toml" ]] ||
      die "protected herdr config is invalid: $share/config.toml"
  fi
  dev_server_validate_active_sha herdr.runtime
}

herdr_service_state() {
  dev_server_service_state "$herdr_platform" "$(herdr_service_name)"
}

herdr_socket_live() {
  python3 -c 'import socket, sys
stream = socket.socket(socket.AF_UNIX)
stream.settimeout(2)
stream.connect(sys.argv[1])' "$1" 2>/dev/null
}

# the pid listening on a unix socket path. the reader drains its producer so
# lsof and ss never see a closed pipe under pipefail.
herdr_socket_listener_pid() {
  local path="$1"
  case "$herdr_platform" in
  macos)
    /usr/sbin/lsof -U -Fpn 2>/dev/null |
      LC_ALL=C awk -v path="$path" '/^p/ {pid = substr($0, 2)} !found && /^n/ && substr($0, 2) == path {print pid; found = 1}'
    ;;
  arch | devbox)
    ss -xlpH 2>/dev/null |
      LC_ALL=C awk -v path="$path" '!found && $5 == path && match($0, /pid=[0-9]+/) {print substr($0, RSTART + 4, RLENGTH - 4); found = 1}'
    ;;
  *) return 1 ;;
  esac
}

herdr_has_toml() {
  local -a files=()
  shopt -s nullglob
  files=("$1"/*.toml)
  shopt -u nullglob
  ((${#files[@]} > 0))
}

# named sessions are a second herdr per host: a live one is stopped by its pid,
# a stale socket file is removed. renders one ACTION per socket; returns 0 when any.
herdr_render_session_sockets() {
  local sessions="$1"
  local socket pid found=0
  local -a sockets=()

  shopt -s nullglob
  sockets=("$sessions"/*/herdr.sock)
  shopt -u nullglob
  for socket in "${sockets[@]}"; do
    found=1
    if herdr_socket_live "$socket"; then
      pid="$(herdr_socket_listener_pid "$socket")" || die 'could not identify the process holding a named session socket'
      [[ "$pid" =~ ^[1-9][0-9]*$ ]] || die 'could not identify the process holding a named session socket'
      render_result ACTION herdr.runtime \
        "unmanaged named session $socket is running; stopping ends its terminals: kill -TERM $pid, then rerun apply"
    else
      render_result ACTION herdr.runtime "stale named session socket $socket; remove it, then rerun apply"
    fi
  done
  ((found))
}

herdr_render_changed_inputs() {
  render_result ACTION herdr.runtime \
    "inputs changed; stopping ends every herdr terminal and its agents: $(herdr_stop_command), then rerun apply; do not run bare herdr in between"
}

herdr_preflight() {
  local platform="$1"
  local home share config_dir name value pid state actions=0

  case "$platform" in macos | arch | devbox) ;; *) die "unsupported herdr platform: $platform" ;; esac
  herdr_platform="$platform"
  herdr_preflight_admitted=0
  home="$(dev_server_home)"
  share="$home/.local/share/herdr"
  config_dir="$home/.config/herdr"
  herdr_validate_declared_inputs "$platform" "$home"
  herdr_validate_protected_paths "$home"
  case "$platform" in
  macos)
    require_cmd launchctl
    # launchd passes setenv values to every agent; herdr would honor them over the unit.
    for name in HERDR_SESSION HERDR_SOCKET_PATH HERDR_CONFIG_PATH HERDR_CLIENT_SOCKET_PATH XDG_CONFIG_HOME XDG_STATE_HOME; do
      value="$(launchctl getenv "$name" 2>/dev/null)" || value=''
      [[ -z "$value" ]] || {
        render_result ACTION herdr.runtime "launchd environment sets $name; run launchctl unsetenv $name, then rerun apply"
        actions=1
      }
    done
    ;;
  arch | devbox)
    require_cmd systemctl ss
    if ! systemctl --user show-environment >/dev/null; then
      render_result ACTION herdr.runtime 'start the user session, then rerun apply'
      return 2
    fi
    ;;
  esac
  state="$(herdr_service_state)" || die 'could not observe herdr service state'
  # residue is reported, never deleted or reset. first managed activation means no recorded identity.
  if [[ ! -f "$(dev_server_active_dir)/herdr.runtime.sha256" && -e "$config_dir/session.json" ]]; then
    render_result ACTION herdr.runtime \
      "unmanaged session snapshot $config_dir/session.json would recreate its shells at first start; move it aside, then rerun apply"
    actions=1
  fi
  if herdr_has_toml "$config_dir/agent-detection"; then
    render_result ACTION herdr.config \
      "agent-detection override $config_dir/agent-detection may supersede bundled codex and claude detection; move it aside, then rerun apply"
    actions=1
  fi
  if herdr_has_toml "$home/.local/state/herdr/agent-detection/remote"; then
    render_result ACTION herdr.runtime \
      "agent-detection state $home/.local/state/herdr/agent-detection/remote may override bundled codex and claude detection; move it aside, then rerun apply"
    actions=1
  fi
  if herdr_render_session_sockets "$config_dir/sessions"; then
    actions=1
  fi
  # a live default socket must belong to the service's main pid; anything else is unmanaged.
  if [[ -S "$config_dir/herdr.sock" ]] && herdr_socket_live "$config_dir/herdr.sock"; then
    pid="$(herdr_socket_listener_pid "$config_dir/herdr.sock")" || die 'could not identify the process holding the herdr socket'
    [[ "$pid" =~ ^[1-9][0-9]*$ ]] || die 'could not identify the process holding the herdr socket'
    if [[ "$state" != active || "$pid" != "$(dev_server_service_main_pid "$platform" "$(herdr_service_name)")" ]]; then
      render_result ACTION herdr.runtime \
        "unmanaged server (pid $pid) holds the socket; stopping ends its terminals: kill -TERM $pid, then rerun apply"
      actions=1
    fi
  fi
  if [[ "$state" == active ]] && ! dev_server_active_sha_matches herdr.runtime "$herdr_desired_identity"; then
    # stage the release now, so the operator's stop only ever precedes a promotion.
    herdr_prepare_directories "$home" "$platform"
    dev_server_acquire_lock "$share/.apply.lock" 8 herdr
    herdr_stage_release "$home"
    exec 8>&-
    herdr_render_changed_inputs
    actions=1
  fi
  ((actions == 0)) || return 2
  herdr_preflight_admitted=1
}

herdr_prepare_directories() {
  local home="$1"
  local platform="$2"

  dev_server_directory_changed=0
  dev_server_reconcile_directory "$home/.local" 0755
  dev_server_reconcile_directory "$home/.local/bin" 0755
  dev_server_reconcile_directory "$home/.local/share" 0755
  dev_server_reconcile_directory "$home/.local/share/herdr" 0700
  dev_server_reconcile_directory "$home/.local/share/herdr/artifacts" 0700
  dev_server_reconcile_directory "$home/.local/share/herdr/releases" 0700
  dev_server_reconcile_directory "$home/.local/state" 0755
  dev_server_reconcile_directory "$home/.local/state/dev-server" 0700
  dev_server_reconcile_directory "$home/.local/state/dev-server/active" 0700
  dev_server_reconcile_directory "$home/.local/state/herdr" 0700
  dev_server_reconcile_directory "$home/.config" 0755
  # mode only: the directory (and devbox's group-owned sessions tree) keeps its owner and group.
  dev_server_reconcile_directory "$home/.config/herdr" 0700
  if [[ "$platform" == macos ]]; then
    dev_server_reconcile_directory "$home/Library" 0755
    dev_server_reconcile_directory "$home/Library/LaunchAgents" 0755
  else
    dev_server_reconcile_directory "$home/.config/systemd" 0755
    dev_server_reconcile_directory "$home/.config/systemd/user" 0755
  fi
  ((dev_server_directory_changed == 0)) ||
    render_result CHANGED herdr.directories 'private directory topology installed'
}

# stages the pinned executable under ARTIFACT (…/artifacts/<sha256>/herdr).
# 0 reused or staged; 1 download/io failure; 2 digest mismatch; 5 version
# mismatch; 6 cached artifact invalid. never touches current, units, or config.
herdr_prepare_artifact() {
  local stage="$1"
  local version="$2"
  local url="$3"
  local binary_sha="$4"
  local artifact="$5"
  local download="$stage/herdr.download"
  local payload="$stage/artifact"
  local observed

  if [[ -e "$artifact" || -L "$artifact" ]]; then
    [[ -d "$artifact" && ! -L "$artifact" && -f "$artifact/herdr" && ! -L "$artifact/herdr" ]] || return 6
    [[ "$(file_mode "$artifact/herdr")" == 755 ]] || return 6
    [[ "$(dev_server_sha256 "$artifact/herdr")" == "$binary_sha" ]] || return 6
    return 0
  fi
  dev_server_download "$url" "$download" || return 1
  [[ "$(dev_server_sha256 "$download")" == "$binary_sha" ]] || return 2
  chmod 0755 "$download" || return 1
  observed="$("$download" --version 2>/dev/null && printf .)" || return 5
  [[ "$observed" == "herdr ${version#v}"$'\n.' ]] || return 5
  mkdir -m 0700 "$payload" || return 1
  install -m 0755 "$download" "$payload/herdr" || return 1
  rm -f -- "$download" || return 1
  mv "$payload" "$artifact"
}

herdr_generation_owned() {
  local path="$1"
  local name entries

  name="$(basename "$path")"
  [[ "$name" =~ ^v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})-([0-9a-f]{64})$ ]] || return 1
  [[ -d "$path" && ! -L "$path" ]] || return 1
  entries="$(find "$path" -mindepth 1 -maxdepth 1 -print | sed "s#^$path/##")" || return 1
  [[ "$entries" == herdr && -f "$path/herdr" && ! -L "$path/herdr" ]] || return 1
  [[ "$(file_mode "$path/herdr" 2>/dev/null)" == 755 ]] || return 1
  [[ "$(dev_server_sha256 "$path/herdr")" == "${BASH_REMATCH[4]}" ]]
}

# stages the artifact and the immutable generation for the pinned release under
# the caller's lock; promotes nothing. dies on any admission failure.
herdr_stage_release() {
  local home="$1"
  local share="$home/.local/share/herdr"
  local stage artifact generation preparation_status=0

  dev_server_remove_stale_stages "$share" || die 'stale herdr staging state is invalid'
  stage="$(mktemp -d "$share/.apply.stage.XXXXXX")" || die 'could not create herdr staging directory'
  chmod 0700 "$stage" || die 'could not secure the herdr staging directory'
  artifact="$share/artifacts/$herdr_binary_sha"
  if herdr_prepare_artifact "$stage" "$herdr_version" "$herdr_url" "$herdr_binary_sha" "$artifact"; then
    preparation_status=0
  else
    preparation_status=$?
  fi
  if ((preparation_status != 0)); then
    dev_server_remove_stage "$share" "$stage"
    case "$preparation_status" in
    2) die 'herdr binary checksum differs from the release pin' ;;
    5) die 'herdr binary identity differs from the release pin' ;;
    6) die "herdr cached artifact is invalid: $artifact" ;;
    *) die 'could not prepare the herdr release' ;;
    esac
  fi
  herdr_generation_name="$herdr_version-$herdr_binary_sha"
  generation="$share/releases/$herdr_generation_name"
  if [[ -e "$generation" || -L "$generation" ]]; then
    if ! herdr_generation_owned "$generation" || ! cmp -s "$artifact/herdr" "$generation/herdr"; then
      dev_server_remove_stage "$share" "$stage"
      die 'immutable herdr generation differs from its admitted release'
    fi
  else
    mkdir -m 0700 "$stage/generation" &&
      install -m 0755 "$artifact/herdr" "$stage/generation/herdr" &&
      mv "$stage/generation" "$generation" || {
      dev_server_remove_stage "$share" "$stage"
      die 'could not promote the herdr generation'
    }
    render_result INSTALLED herdr.runtime "$herdr_generation_name"
  fi
  dev_server_remove_stage "$share" "$stage" || die 'could not remove the herdr staging directory'
}

herdr_ping() {
  python3 - "$1" "$2" <<'PY'
import json
import socket
import sys

stream = socket.socket(socket.AF_UNIX)
stream.settimeout(max(float(sys.argv[2]), 0.5))
stream.connect(sys.argv[1])
stream.sendall(b'{"id":"dev-server","method":"ping","params":{}}\n')
buffer = b""
while not buffer.endswith(b"\n"):
    chunk = stream.recv(65536)
    if not chunk:
        break
    buffer += chunk
    if len(buffer) > 65536:
        raise SystemExit(1)
result = json.loads(buffer.decode("utf-8")).get("result")
if not isinstance(result, dict) or result.get("type") != "pong":
    raise SystemExit(1)
if not isinstance(result.get("version"), str) or not isinstance(result.get("protocol"), int):
    raise SystemExit(1)
print(result["version"], result["protocol"])
PY
}

herdr_manifests_bundled() {
  local binary="$1"
  local socket="$2"
  HERDR_SOCKET_PATH="$socket" "$binary" server agent-manifests --json 2>/dev/null |
    python3 -c '
import json
import sys

manifests = json.load(sys.stdin)["result"]["manifests"]
kinds = {item.get("agent"): item.get("source_kind") for item in manifests}
raise SystemExit(0 if kinds.get("codex") == "bundled" and kinds.get("claude") == "bundled" else 1)'
}

# starts the absent or inactive service; renders nothing. UNIT_CHANGED forces a
# reload of the definition; WAS_ENABLED 0 enables it first.
herdr_start_service() {
  local platform="$1"
  local home="$2"
  local state="$3"
  local unit_changed="$4"
  local was_enabled="$5"
  local unit_target domain

  unit_target="$(herdr_unit_target "$platform" "$home")"
  case "$platform" in
  arch | devbox)
    if ((unit_changed)) || [[ "$state" == absent ]]; then
      systemctl --user daemon-reload || return 1
    fi
    if ((was_enabled == 0)); then
      systemctl --user enable herdr.service || return 1
      herdr_enablement_changed=1
    fi
    systemctl --user start herdr.service || return 1
    ;;
  macos)
    domain="gui/$(id -u)"
    if ((was_enabled == 0)); then
      launchctl enable "$domain/dev.niels.herdr" || return 1
      herdr_enablement_changed=1
    fi
    if [[ "$state" != absent ]] && ((unit_changed)); then
      launchctl bootout "$domain/dev.niels.herdr" || return 1
      state=absent
    fi
    if [[ "$state" == absent ]]; then
      launchctl bootstrap "$domain" "$unit_target" || return 1
    else
      launchctl kickstart "$domain/dev.niels.herdr" || return 1
    fi
    ;;
  *) return 1 ;;
  esac
}

herdr_stop_service() {
  case "$herdr_platform" in
  macos) launchctl bootout "gui/$(id -u)/dev.niels.herdr" >/dev/null 2>&1 || true ;;
  arch | devbox) systemctl --user stop herdr.service >/dev/null 2>&1 || true ;;
  esac
}

# verifies a started server within ten seconds: ping identity, bundled
# detection, socket mode and owner. prints the STARTED detail on success.
herdr_verify_started() {
  local platform="$1"
  local home="$2"
  local share="$home/.local/share/herdr"
  local socket="$home/.config/herdr/herdr.sock"
  local deadline pong='' version protocol state pid

  deadline=$((SECONDS + 10))
  while ((SECONDS < deadline)); do
    state="$(herdr_service_state)" || return 1
    if [[ "$state" == active ]] && pong="$(herdr_ping "$socket" "$((deadline - SECONDS))" 2>/dev/null)"; then
      break
    fi
    pong=''
    sleep 1
  done
  [[ -n "$pong" ]] || return 1
  read -r version protocol <<<"$pong"
  [[ "$version" == "${herdr_version#v}" && "$protocol" == 22 ]] || return 1
  herdr_manifests_bundled "$share/current/herdr" "$socket" || return 1
  [[ "$(stat -c '%a' "$socket" 2>/dev/null || stat -f '%Lp' "$socket" 2>/dev/null)" == 600 ]] || return 1
  pid="$(dev_server_service_main_pid "$platform" "$(herdr_service_name)")" || return 1
  [[ "$(herdr_socket_listener_pid "$socket")" == "$pid" ]] || return 1
  printf 'ping herdr %s protocol %s; bundled codex and claude detection\n' "$version" "$protocol"
}

# undoes a failed activation: stops only the candidate this apply started, puts
# the unit, config, pointers and snapshot back, and when a prior activation was
# recorded restarts and verifies that prior server. 0 restored (and prior
# running when recorded); 3 prior inputs restored but herdr remains stopped;
# 1 the restore itself failed.
herdr_restore() {
  local platform="$1"
  local home="$2"
  local stage="$3"
  local prior_current="$4"
  local command_installed="$5"
  local snapshot_present="$6"
  local was_enabled="$7"
  local recorded="$8"
  local share="$home/.local/share/herdr"
  local unit_target state

  unit_target="$(herdr_unit_target "$platform" "$home")"
  herdr_stop_service
  if ((was_enabled == 0 && recorded == 0)); then
    case "$platform" in
    macos) launchctl disable "gui/$(id -u)/dev.niels.herdr" >/dev/null 2>&1 || return 1 ;;
    arch | devbox) systemctl --user disable herdr.service >/dev/null 2>&1 || return 1 ;;
    esac
  fi
  dev_server_restore_file "$unit_target" "$stage/unit-backup" 0644 || return 1
  [[ "$platform" == macos ]] || systemctl --user daemon-reload >/dev/null 2>&1 || true
  dev_server_restore_file "$share/config.toml" "$stage/config-backup" 0600 || return 1
  if [[ -n "$prior_current" ]]; then
    dev_server_atomic_symlink "$share/current" "$prior_current" || return 1
  else
    dev_server_remove_link "$share/current" || return 1
  fi
  if ((command_installed)); then
    dev_server_remove_link "$home/.local/bin/herdr" || return 1
  fi
  if ((snapshot_present == 0)) && [[ -e "$home/.config/herdr/session.json" ]]; then
    rm -f -- "$home/.config/herdr/session.json" || return 1
  fi
  state="$(herdr_service_state)" || return 1
  if ((recorded == 0)); then
    [[ "$state" != active ]]
    return
  fi
  # the prior inputs are back; run them again as skid does after a failed upgrade.
  herdr_start_service "$platform" "$home" "$state" 1 1 || return 3
  herdr_verify_started "$platform" "$home" >/dev/null || return 3
  if ((was_enabled == 0)); then
    case "$platform" in
    macos) launchctl disable "gui/$(id -u)/dev.niels.herdr" >/dev/null 2>&1 || return 1 ;;
    arch | devbox) systemctl --user disable herdr.service >/dev/null 2>&1 || return 1 ;;
    esac
  fi
}

# keeps the current generation and the prior current one, with their artifacts.
herdr_retain() {
  local share="$1"
  local current="$2"
  local prior="$3"
  local path name

  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    [[ "$name" != "$current" && "$name" != "$prior" ]] || continue
    herdr_generation_owned "$path" || return 1
    rm -R -- "$path" || return 1
  done < <(find "$share/releases" -mindepth 1 -maxdepth 1 -print0)
  while IFS= read -r -d '' path; do
    name="$(basename "$path")"
    [[ "$name" =~ ^[0-9a-f]{64}$ && -d "$path" && ! -L "$path" ]] || continue
    [[ "$current" != *"-$name" && "$prior" != *"-$name" ]] || continue
    [[ "$(find "$path" -mindepth 1 -maxdepth 1 -print | sed "s#^$path/##")" == herdr ]] || continue
    rm -R -- "$path" || return 1
  done < <(find "$share/artifacts" -mindepth 1 -maxdepth 1 -print0)
}

# signal handler for the start-to-record window of herdr_apply; runs in its scope.
herdr_abandon_candidate() {
  herdr_restore "$platform" "$home" "$stage" "$prior_current" "$command_installed" \
    "$snapshot_present" "$was_enabled" "$recorded" >/dev/null 2>&1 || true
  dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true
}

herdr_apply() {
  local platform="$1"
  local home share config_dir unit_source unit_target state stage detail
  local enablement_observation=0 was_enabled=0 recorded=0 restore_status=0
  local prior_current='' pointer_changed=0 command_installed=0 snapshot_present=0
  local config_status='UP TO DATE' unit_status='UP TO DATE' unit_changed=0
  local saved_hup saved_int saved_term

  [[ "$platform" == "$herdr_platform" && "$herdr_preflight_admitted" == 1 ]] ||
    die 'herdr preflight did not admit this apply'
  home="$(dev_server_home)"
  share="$home/.local/share/herdr"
  config_dir="$home/.config/herdr"
  unit_source="$(herdr_unit_source "$platform")"
  unit_target="$(herdr_unit_target "$platform" "$home")"
  herdr_prepare_directories "$home" "$platform"
  dev_server_acquire_lock "$share/.apply.lock" 8 herdr
  state="$(herdr_service_state)" || die 'could not observe herdr service state'
  if [[ "$state" == active ]]; then
    # the guard for a server that started between preflight and apply.
    if ! dev_server_active_sha_matches herdr.runtime "$herdr_desired_identity"; then
      herdr_render_changed_inputs
      exec 8>&-
      return 2
    fi
    exec 8>&-
    return 0
  fi
  herdr_stage_release "$home"
  [[ ! -f "$(dev_server_active_dir)/herdr.runtime.sha256" ]] || recorded=1

  # promotion: the service is absent or inactive, so pointers and inputs may change.
  stage="$(mktemp -d "$share/.apply.stage.XXXXXX")" || die 'could not create herdr staging directory'
  chmod 0700 "$stage" || die 'could not secure the herdr staging directory'
  [[ ! -e "$config_dir/session.json" ]] || snapshot_present=1
  [[ ! -L "$share/current" ]] || prior_current="$(readlink "$share/current")"
  [[ -L "$home/.local/bin/herdr" ]] || command_installed=1
  if dev_server_service_enabled "$platform" "$(herdr_service_name)"; then
    was_enabled=1
  else
    enablement_observation=$?
    ((enablement_observation == 1)) || {
      dev_server_remove_stage "$share" "$stage"
      die 'could not observe herdr service enablement'
    }
  fi
  dev_server_snapshot_file "$unit_target" "$stage/unit-backup" 0644 || {
    dev_server_remove_stage "$share" "$stage"
    die 'herdr unit target is invalid'
  }
  dev_server_snapshot_file "$share/config.toml" "$stage/config-backup" 0600 || {
    dev_server_remove_stage "$share" "$stage"
    die 'herdr config target is invalid'
  }
  if [[ "$prior_current" != "releases/$herdr_generation_name" ]]; then
    dev_server_atomic_symlink "$share/current" "releases/$herdr_generation_name" || {
      dev_server_remove_stage "$share" "$stage"
      die 'could not activate the herdr generation pointer'
    }
    pointer_changed=1
  fi
  dev_server_atomic_symlink "$home/.local/bin/herdr" '../share/herdr/current/herdr' || {
    dev_server_remove_stage "$share" "$stage"
    die 'could not install the herdr command link'
  }
  atomic_install_file "$(dev_server_assets_dir)/herdr/config.toml" "$share/config.toml" 0600 || {
    dev_server_remove_stage "$share" "$stage"
    die 'could not install the herdr managed config'
  }
  config_status="$dev_server_install_status"
  atomic_install_file "$unit_source" "$unit_target" 0644 || {
    dev_server_remove_stage "$share" "$stage"
    die 'could not install the herdr unit'
  }
  unit_status="$dev_server_install_status"
  [[ "$unit_status" == 'UP TO DATE' ]] || unit_changed=1

  # an interrupted start leaves the prior inputs, never a half-promoted candidate.
  saved_hup="$(trap -p HUP)"
  saved_int="$(trap -p INT)"
  saved_term="$(trap -p TERM)"
  trap 'herdr_abandon_candidate; exit 129' HUP
  trap 'herdr_abandon_candidate; exit 130' INT
  trap 'herdr_abandon_candidate; exit 143' TERM
  herdr_enablement_changed=0
  if herdr_start_service "$platform" "$home" "$state" "$unit_changed" "$was_enabled" &&
    detail="$(herdr_verify_started "$platform" "$home")"; then
    :
  else
    if herdr_restore "$platform" "$home" "$stage" "$prior_current" "$command_installed" \
      "$snapshot_present" "$was_enabled" "$recorded"; then
      restore_status=0
    else
      restore_status=$?
    fi
    dev_server_remove_stage "$share" "$stage"
    case "$recorded:$restore_status" in
    0:0) die 'herdr first activation failed; the candidate was stopped and its unit removed' ;;
    0:*) die 'herdr first activation failed and the candidate could not be removed safely' ;;
    1:0) die 'herdr activation failed; the candidate was stopped and the prior herdr was restored and restarted' ;;
    1:3) die 'herdr activation failed; the prior inputs were restored but herdr remains stopped; rerun apply' ;;
    *) die 'herdr activation failed and the prior inputs could not be restored; herdr remains stopped' ;;
    esac
  fi
  ((pointer_changed == 0)) || render_result UPDATED herdr.runtime "$herdr_generation_name"
  ((command_installed == 0)) || render_result INSTALLED herdr.command "$home/.local/bin/herdr"
  [[ "$config_status" == 'UP TO DATE' ]] || render_result "$config_status" herdr.config "$share/config.toml"
  [[ "$unit_status" == 'UP TO DATE' ]] || render_result "$unit_status" herdr.unit "$unit_target"
  ((herdr_enablement_changed == 0)) || render_result CHANGED herdr.unit 'enabled at login'
  render_result STARTED herdr.runtime "$detail"
  dev_server_record_active_sha herdr.runtime "$herdr_desired_identity" || {
    dev_server_remove_stage "$share" "$stage"
    die 'could not record the active herdr runtime identity'
  }
  dev_server_restore_signal_trap HUP "$saved_hup"
  dev_server_restore_signal_trap INT "$saved_int"
  dev_server_restore_signal_trap TERM "$saved_term"
  herdr_retain "$share" "$herdr_generation_name" "${prior_current#releases/}" || {
    dev_server_remove_stage "$share" "$stage"
    die 'herdr release retention found an unowned generation'
  }
  dev_server_remove_stage "$share" "$stage" || die 'could not remove the herdr staging directory'
  exec 8>&-
}
