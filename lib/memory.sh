#!/usr/bin/env bash

memory_install() {
  local rows status=0 line result subject detail
  if rows="$(_memory_install "$@")"; then :; else status=$?; fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    result="${line%%  *}"
    case "$result" in
    INSTALLED | UPDATED | CHANGED | STARTED | RESTARTED | DEFERRED | ACTION | ERROR)
      detail="${line#*  }"
      subject="${detail%%: *}"
      render_result "$result" "$subject" "${detail#*: }"
      ;;
    *) printf '%s\n' "$line" ;;
    esac
  done <<<"$rows"
  return "$status"
}

_memory_install() (
  local platform="$1" bundle="$2" owner_home base config stage repository revision release
  local launcher unit service desired state candidate target previous='' uv new_release=''
  local changed=0 mode
  [[ -d "$bundle" ]] || {
    render_result ACTION memory 'render and supply the private memory bundle before activation'
    return 2
  }
  owner_home="$(dev_server_home)"
  base="$owner_home/.local/share/jarvis-memory"
  config="$owner_home/.config/jarvis-memory"
  ensure_directory "$owner_home/.config" 0755 >/dev/null || return 1
  ensure_directory "$base" 0700 >/dev/null || return 1
  ensure_directory "$config" 0700 >/dev/null || return 1
  dev_server_strict_json_file "$(dev_server_assets_dir)/memory/release-pin.json" 4096 || return 1
  IFS=$'\t' read -r repository revision < <(python3 - "$(dev_server_assets_dir)/memory/release-pin.json" <<'PY'
import json, re, sys
value = json.load(open(sys.argv[1]))
if value.keys() != {"repository", "revision"} or value["repository"] != "https://github.com/NielsdaWheelz/jarvis.git":
    raise SystemExit(1)
if value["revision"] is not None and not re.fullmatch(r"[0-9a-f]{40}", value["revision"]):
    raise SystemExit(1)
print(value["repository"] + "\t" + (value["revision"] or "pending"))
PY
  ) || return 1
  [[ "$revision" != pending ]] || {
    render_result ACTION memory 'qualify and declare the exact central Jarvis revision before installing collectors'
    return 2
  }
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  if [[ -L "$base/current" ]]; then
    previous="$(readlink "$base/current")"
    [[ "$previous" =~ ^release-[0-9a-f]{40}$ ]] || return 1
  fi
  stage="$(mktemp -d "$base/.input.XXXXXX")" || return 1
  trap 'rm -R -- "$stage"; [[ -z "$new_release" || ! -e "$new_release" ]] || rm -R -- "${new_release:?}"' EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  release="$base/release-$revision"
  if [[ ! -x "$release/.venv/bin/jarvis-memory-collector" ]]; then
    [[ ! -e "$release" ]] || {
      render_result ACTION memory "repair the incomplete task-owned collector release at $release"
      return 2
    }
    uv="$(command -v uv || true)"
    if [[ -z "$uv" ]]; then
      [[ -x "$base/bootstrap/bin/python" ]] || python3 -m venv "$base/bootstrap" || return 1
      "$base/bootstrap/bin/python" -m pip --disable-pip-version-check install --quiet --upgrade uv || return 1
      uv="$base/bootstrap/bin/uv"
    fi
    new_release="$release"
    git init --quiet "$release" &&
      git -C "$release" remote add origin "$repository" &&
      git -C "$release" fetch --quiet --depth=1 origin "$revision" &&
      git -C "$release" checkout --quiet --detach "$revision" || return 1
    [[ "$(git -C "$release" rev-parse HEAD)" == "$revision" ]] || return 1
    "$uv" sync --project "$release" --frozen --no-dev --python 3.12 || return 1
    "$release/.venv/bin/jarvis-memory-collector" --help >/dev/null || return 1
    render_result INSTALLED memory.collector "central Jarvis source $revision"
  fi
  [[ "$(git -C "$release" rev-parse HEAD)" == "$revision" ]] || return 1
  "$release/.venv/bin/python" - "$bundle/collector.json" <<'PY' || return 1
from pathlib import Path
import sys
from jarvis.collector import CollectorConfig
CollectorConfig.load(Path(sys.argv[1]))
PY
  "$release/.venv/bin/python" "$(dev_server_assets_dir)/memory/profile-config.py" \
    "$bundle/profiles.json" "$bundle/collector.json" "$owner_home" \
    "$stage/profiles" >"$stage/profile-paths" || return 1
  while IFS=$'\t' read -r candidate target; do
    [[ -n "$candidate" ]] || continue
    install_managed_file "$candidate" "$target" 0600 memory.profiles || return 1
  done <"$stage/profile-paths"
  install_managed_file "$bundle/clients.env" "$config/clients.env" 0600 memory.profiles || return 1
  ai_install_instructions || return 1
  launcher="$base/collector-launch"
  python3 - "$release" "$config" >"$stage/launcher" <<'PY' || return 1
import shlex, sys
release, config = sys.argv[1:]
print("#!/bin/sh\nset -eu")
print(". " + shlex.quote(config + "/collector.env"))
print("export PATH=" + shlex.quote(str(__import__('pathlib').Path(config).parents[1]) + "/.local/bin:/usr/local/bin:/usr/bin:/bin"))
print("exec " + shlex.quote(release + "/.venv/bin/jarvis-memory-collector") + " --config " + shlex.quote(config + "/collector.json"))
PY
  if [[ "$platform" == macos ]]; then
    # shellcheck disable=SC2154 # shared deployment identity owns this value.
    service="$dev_server_fleet_label_prefix.jarvis-memory-collector"
    unit="$owner_home/Library/LaunchAgents/$service.plist"
    python3 - "$service" "$launcher" >"$stage/unit" <<'PY' || return 1
import plistlib, sys
plistlib.dump({"Label":sys.argv[1], "ProgramArguments":[sys.argv[2]], "RunAtLoad":True,
              "KeepAlive":True, "ThrottleInterval":10}, sys.stdout.buffer)
PY
    plutil -lint "$stage/unit" >/dev/null || return 1
  else
    service=jarvis-memory-collector.service
    ensure_directory "$owner_home/.config/systemd" 0755 >/dev/null || return 1
    unit="$owner_home/.config/systemd/user/$service"
    python3 - "$(dev_server_assets_dir)/memory/jarvis-memory-collector.service" "$launcher" >"$stage/unit" <<'PY' || return 1
import json, sys
from pathlib import Path
print(Path(sys.argv[1]).read_text().replace("@LAUNCHER@", json.dumps(sys.argv[2], ensure_ascii=False).replace("%", "%%")), end="")
PY
  fi
  desired="$(
    printf '%s\n' "$revision"
    cat "$stage/launcher" "$stage/unit" "$bundle/collector.json" "$bundle/collector.env"
  )"
  desired="$(printf '%s' "$desired" | dev_server_sha256_stream)" || return 1
  while IFS=$'\t' read -r candidate target mode; do
    if [[ ! -f "$target" || -L "$target" ]] ||
      ! cmp -s "$candidate" "$target" || [[ "$(file_mode "$target")" != "$mode" ]]; then
      changed=1
    fi
  done <<EOF
$bundle/collector.json	$config/collector.json	600
$bundle/collector.env	$config/collector.env	600
$stage/launcher	$launcher	755
$stage/unit	$unit	644
EOF
  dev_server_prepare_active_dir || return 1
  state="$(dev_server_service_state "$platform" "$service")" || return 1
  if ((changed)) || ! dev_server_active_sha_matches memory.collector "$desired" || [[ "$state" != active ]]; then
    dev_server_stop_service "$platform" "$service" || return 1
    for candidate in "$base"/release-*; do
      [[ "${candidate##*/}" =~ ^release-[0-9a-f]{40}$ ]] || continue
      [[ "$candidate" == "$release" || "${candidate##*/}" == "$previous" ]] && continue
      [[ ! -d "$candidate" ]] || rm -R -- "$candidate" || return 1
    done
    new_release=''
    install_managed_file "$bundle/collector.json" "$config/collector.json" 0600 memory.collector || return 1
    install_managed_file "$bundle/collector.env" "$config/collector.env" 0600 memory.collector || return 1
    install_managed_file "$stage/launcher" "$launcher" 0755 memory.collector || return 1
    ensure_directory "$(dirname "$unit")" 0755 >/dev/null || return 1
    install_managed_file "$stage/unit" "$unit" 0644 memory.collector || return 1
    if [[ "$platform" == macos ]]; then
      launchctl enable "gui/$(id -u)/$service" || return 1
      launchctl bootstrap "gui/$(id -u)" "$unit" || return 1
    else
      systemctl --user daemon-reload || return 1
      systemctl --user enable --now "$service" || return 1
    fi
    render_result STARTED memory.collector 'owner collector with central durable progress'
  fi
  if ! (
    # shellcheck disable=SC1091 # the private generated bearer file is installed above.
    source "$config/collector.env"
    "$release/.venv/bin/python" - "$config/collector.json" <<'PY'
import os, sys, httpx
from pathlib import Path
from jarvis.collector import CollectorConfig
from provider_runtime.agent_runtime.archive import ARCHIVE_CONTRACT_REVISION
config = CollectorConfig.load(Path(sys.argv[1]))
try:
    with httpx.Client(trust_env=False, follow_redirects=False, timeout=10) as client:
        result = client.get(config.service_url + "/v1/memory/lanes",
            headers={"Authorization":"Bearer " + os.environ[config.bearer_env]})
    assert result.status_code == 200
    assert result.json()["contract_revision"] == ARCHIVE_CONTRACT_REVISION
except (httpx.HTTPError, ValueError, KeyError, AssertionError):
    raise SystemExit(1) from None
PY
  ); then
    render_result DEFERRED memory.collector 'collector started; authenticated private endpoint verification remains pending'
    return 0
  fi
  [[ "$(dev_server_service_state "$platform" "$service")" == active ]] || return 1
  dev_server_record_active_sha memory.collector "$desired" || return 1
  dev_server_atomic_symlink "$base/current" "release-$revision" || return 1
  if [[ -n "$previous" && "$previous" != "release-$revision" ]]; then
    rm -R -- "${base:?}/$previous" || return 1
  fi
)
