#!/usr/bin/env bash

# skid owns installation, services, dependencies, shell integration and removal.
# dev-server owns one personal release pin and the desired yaml on the hub.
skidbladnir_apply() {
  local platform="$1" home assets pin version source_sha installer_sha config private android_push desired_config status
  case "$platform" in macos | arch | devbox) ;; *) return 64 ;; esac
  home="$(dev_server_home)"
  assets="$(dev_server_assets_dir)/skidbladnir"
  pin="$assets/release-pin.json"
  dev_server_strict_json_file "$pin" 4096 || return 1
  pin="$(
    python3 - "$pin" <<'PY'
import json
import re
import sys
value = json.load(open(sys.argv[1], encoding="utf-8"))
if (not isinstance(value, dict) or set(value) != {
        "schemaVersion", "version", "sourceSha", "installerSha256"} or
        type(value["schemaVersion"]) is not int or value["schemaVersion"] != 1 or
        not isinstance(value["version"], str) or
        re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", value["version"]) is None or
        any(not isinstance(value[key], str) or re.fullmatch(pattern, value[key]) is None
            for key, pattern in (("sourceSha", r"[0-9a-f]{40}"),
                                 ("installerSha256", r"[0-9a-f]{64}")))):
    raise SystemExit("invalid standalone skid release pin")
print("\t".join(value[key] for key in ("version", "sourceSha", "installerSha256")))
PY
  )" || return 1
  IFS=$'\t' read -r version source_sha installer_sha <<<"$pin"
  if [[ "$platform" == devbox ]]; then
    config="${XDG_CONFIG_HOME:-$home/.config}/skidbladnir"
    private="${XDG_CONFIG_HOME:-$home/.config}/dev-server"
    [[ ! -e "$private/skidbladnir.yaml" && ! -L "$private/skidbladnir.yaml" ]] ||
      die 'the complete skid yaml override is retired; keep only its android_push block in skidbladnir-android-push.yaml'
    android_push="$private/skidbladnir-android-push.yaml"
    if [[ -e "$android_push" || -L "$android_push" ]]; then
      [[ -f "$android_push" && ! -L "$android_push" ]] || die 'skid android_push yaml is not a regular file'
      awk '/^[^[:space:]#]/ && $0 != "android_push:" { bad = 1 } END { exit bad }' "$android_push" ||
        die 'skid android_push yaml may hold only the top-level android_push key'
    else
      android_push=
    fi
  fi
  (
    local stage
    stage="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-skid.XXXXXX")" || return 1
    trap 'rm -R -- "$stage"' EXIT
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM
    curl --connect-timeout 15 --max-time 60 --fail --silent --show-error \
      --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
      "https://raw.githubusercontent.com/NielsdaWheelz/skidbladnir/$source_sha/scripts/install" \
      -o "$stage/install" || return 1
    [[ "$(dev_server_sha256 "$stage/install")" == "$installer_sha" ]] ||
      die 'standalone skid bootstrap checksum differs from the reviewed pin'
    bash "$stage/install" "$version" || return $?
  ) || return $?
  # Only the authoritative hub receives desired configuration: the committed yaml
  # plus the host's private android_push block. membership and generated state
  # belong to skid; enrollment is an explicit cutover operation.
  if [[ "$platform" == devbox ]]; then
    ensure_directory "$config" 0700 || return 1
    desired_config="$(mktemp "${TMPDIR:-/tmp}/dev-server-skid-config.XXXXXX")" || return 1
    if cat -- "$assets/config.yaml" ${android_push:+"$android_push"} >"$desired_config" &&
      install_managed_file "$desired_config" "$config/config.yaml" 0600 skid.config; then
      status=0
    else
      status=1
    fi
    rm -f -- "$desired_config"
    ((status == 0)) || return 1
    "$home/.local/bin/skid" apply || return $?
  fi
}

skidbladnir_remove() {
  local home
  home="$(dev_server_home)"
  if [[ -x "$home/.local/bin/skid" ]]; then
    "$home/.local/bin/skid" uninstall
  else
    render_result 'UP TO DATE' skid 'standalone skid is not installed'
  fi
}
