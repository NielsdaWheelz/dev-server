#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
: "${skidbladnir_release_pin_file:=$(dev_server_assets_dir)/skidbladnir/release-pin.json}"

: "${dev_server_install_status:=UP TO DATE}"
: "${dev_server_fleet_label_prefix:=dev.niels}"
: "${dev_server_gateway_port:=7341}"
skidbladnir_unit_changed=0
skidbladnir_activation_status=''
skidbladnir_integration_changed=0
skidbladnir_enablement_changed=0
skidbladnir_command_installed=0
skidbladnir_serve_cli=''
skidbladnir_serve_hostname=''
skidbladnir_serve_json=''
skidbladnir_serve_state=''

skidbladnir_platform_key() {
  case "$1" in
  macos) printf 'darwin-arm64\n' ;;
  arch | devbox) printf 'linux-amd64\n' ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_host_config_source() {
  case "$1" in
  macos) printf '%s/skidbladnir/host-config-macbook.json\n' "$(dev_server_assets_dir)" ;;
  arch) printf '%s/skidbladnir/host-config-arch.json\n' "$(dev_server_assets_dir)" ;;
  devbox) printf '%s/skidbladnir/host-config-devbox.json\n' "$(dev_server_assets_dir)" ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_agent_hooks_source() {
  case "$1" in
  macos) printf '%s/skidbladnir/agent-hooks-macbook.json\n' "$(dev_server_assets_dir)" ;;
  arch) printf '%s/skidbladnir/agent-hooks-arch.json\n' "$(dev_server_assets_dir)" ;;
  devbox) printf '%s/skidbladnir/agent-hooks-devbox.json\n' "$(dev_server_assets_dir)" ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_release_values() {
  local platform="$1"
  local artifact
  artifact="$(skidbladnir_platform_key "$platform")"
  dev_server_strict_json_file "$skidbladnir_release_pin_file" 4096 || return 1

  python3 - "$skidbladnir_release_pin_file" "$artifact" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
artifact = sys.argv[2]
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
        not isinstance(artifacts, dict) or
        sorted(artifacts) != ["darwin-arm64", "linux-amd64"]):
    raise SystemExit(1)
for name in ("darwin-arm64", "linux-amd64"):
    item = artifacts[name]
    expected = (
        "https://github.com/NielsdaWheelz/skidbladnir/releases/download/" +
        f"{version}/skidbladnir-{name}.tar.gz"
    )
    if (not isinstance(item, dict) or sorted(item) != ["sha256", "url"] or
            item.get("url") != expected or not isinstance(item.get("sha256"), str) or
            not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])):
        raise SystemExit(1)
print("\t".join((version, source, artifacts[artifact]["url"],
                  artifacts[artifact]["sha256"], artifact)))
PY
}

skidbladnir_release_manifest_matches() {
  local manifest="$1"
  local platform="$2"
  local source_sha="$3"
  local version="$4"

  dev_server_strict_json_file "$manifest" 4096 || return 1
  python3 - "$manifest" "$platform" "$source_sha" "$version" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
expected = {"platform": sys.argv[2], "sourceSha": sys.argv[3], "version": sys.argv[4]}
raise SystemExit(0 if value == expected else 1)
PY
}

skidbladnir_host_config_valid() {
  local path="$1"
  local platform="$2"
  local runtime home

  case "$platform" in
  macos) runtime=Darwin ;;
  arch | devbox) runtime=Linux ;;
  *) return 1 ;;
  esac
  home="$(dev_server_home)"
  dev_server_strict_json_file "$path" 65536 || return 1
  # deployment-owned facts only: paths under this home, the four account wrappers,
  # permission flags, and the herdr literals the unit renders. the schema is the
  # candidate binary's job (validate-host-config after artifact preparation).
  python3 - "$path" "$runtime" "$home" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
runtime, home = sys.argv[2:]
if not isinstance(value, dict) or value.get("platform") != runtime:
    raise SystemExit(1)
if value.get("herdr") != {"path": home + "/.local/share/herdr/current/herdr",
                          "socketPath": home + "/.config/herdr/herdr.sock",
                          "testedVersion": "herdr 0.9.1"}:
    raise SystemExit(1)
commands = {
    "personal": home + "/bin/codex",
    "work": home + "/bin/codex-work",
    "work2": home + "/bin/codex-work2",
    "claude-work": home + "/bin/claude-work",
}
arguments = {
    "Codex": ["--yolo"],
    "Claude": ["--dangerously-skip-permissions", "--plugin-dir",
               home + "/.local/share/skidbladnir/claude-agent-identity"],
}
signatures = {
    "Codex": [{"executableBase": "codex"},
              {"executableBase": "node", "argument1": home + "/.local/bin/codex"}],
    "Claude": [{"argument0": home + "/.local/bin/claude"}],
}
profiles = value.get("profiles")
if (not isinstance(profiles, list) or not all(isinstance(p, dict) for p in profiles) or
        [p.get("key") for p in profiles] != list(commands)):
    raise SystemExit(1)
for profile in profiles:
    provider = profile.get("provider")
    if (provider not in arguments or profile.get("command") != commands[profile["key"]] or
            profile.get("arguments") != arguments[provider] or
            profile.get("foregroundSignatures") != signatures[provider]):
        raise SystemExit(1)
    for item in profile.get("environment") or []:
        if not isinstance(item, dict) or not str(item.get("value", "")).startswith(home + "/"):
            raise SystemExit(1)
PY
}

skidbladnir_validate_declared_inputs() {
  local platform="$1"
  local hooks host_config path
  local -a regular_files=(
    skidbladnir-launch
    skid-notify
    claude-agent-identity/bin/agent-hook
  )

  case "$platform" in
  macos) regular_files+=(dev.niels.skidbladnir.plist) ;;
  arch | devbox) regular_files+=(skidbladnir.service) ;;
  *) die "unsupported Skidbladnir platform: $platform" ;;
  esac

  require_cmd python3
  skidbladnir_release_values "$platform" >/dev/null ||
    die 'Skidbladnir release pin is invalid'
  host_config="$(skidbladnir_host_config_source "$platform")"
  skidbladnir_host_config_valid "$host_config" "$platform" ||
    die 'Skidbladnir host config is invalid'
  hooks="$(skidbladnir_agent_hooks_source "$platform")"
  dev_server_strict_json_file "$hooks" 65536 ||
    die 'Skidbladnir agent hooks are invalid'
  python3 - "$hooks" <<'PY' || die 'Skidbladnir agent hooks schema is invalid'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
if not isinstance(value, dict) or sorted(value) != ["description", "hooks"]:
    raise SystemExit(1)
if (not isinstance(value["description"], str) or
        not 0 < len(value["description"]) <= 128 or
        not isinstance(value["hooks"], dict) or list(value["hooks"]) != ["SessionStart"]):
    raise SystemExit(1)
events = value["hooks"]["SessionStart"]
if not isinstance(events, list) or len(events) != 1:
    raise SystemExit(1)
event = events[0]
if (not isinstance(event, dict) or sorted(event) != ["hooks", "matcher"] or
        event["matcher"] != "^(startup|resume|clear)$" or
        not isinstance(event["hooks"], list) or len(event["hooks"]) != 1):
    raise SystemExit(1)
hook = event["hooks"][0]
if (not isinstance(hook, dict) or
        sorted(hook) != ["async", "command", "timeout", "type"] or
        hook["type"] != "command" or hook["async"] is not False or hook["timeout"] != 5 or
        not isinstance(hook["command"], str) or not 0 < len(hook["command"]) <= 4096):
    raise SystemExit(1)
PY
  for path in "${regular_files[@]}"; do
    path="$(dev_server_assets_dir)/skidbladnir/$path"
    [[ -f "$path" && ! -L "$path" ]] ||
      die "invalid Skidbladnir declared file: $path"
  done
  for path in \
    claude-agent-identity/.claude-plugin/plugin.json \
    claude-agent-identity/hooks/hooks.json; do
    path="$(dev_server_assets_dir)/skidbladnir/$path"
    dev_server_strict_json_file "$path" 65536 ||
      die "invalid Skidbladnir declared JSON: $path"
  done
  skidbladnir_unit_identity "$platform" >/dev/null ||
    die 'Skidbladnir unit inputs are invalid'
}

skidbladnir_validate_local_state() {
  local home="$1"
  local config="$home/.config/skidbladnir"

  skidbladnir_validate_protected_paths "$home"
  skidbladnir_validate_present_credentials "$config" ||
    die 'existing Skidbladnir credentials are invalid'
  skidbladnir_validate_active_journals "$home" ||
    die 'existing Skidbladnir active identity is invalid'
}

skidbladnir_secret_valid() (
  set +x
  local path="$1"
  local pattern="$2"
  local value framed

  [[ -f "$path" && ! -L "$path" ]] || return 1
  [[ "$(file_mode "$path" 2>/dev/null)" == 600 ]] || return 1
  value="$(cat "$path")" || return 1
  framed="$(cat "$path" && printf .)" || return 1
  [[ "$framed" == "$value"$'\n.' && "$value" =~ $pattern ]]
)

skidbladnir_validate_present_credentials() {
  local config="$1"
  local path

  if [[ -e "$config/machine-handle" || -L "$config/machine-handle" ]]; then
    skidbladnir_secret_valid "$config/machine-handle" '^mh-[0-9a-f]{32}$' ||
      return 1
  fi
  if [[ -e "$config/bearer" || -L "$config/bearer" ]]; then
    skidbladnir_secret_valid "$config/bearer" \
      '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || return 1
  fi
  for path in \
    "$config/android-signing.p12" \
    "$config/android-signing.properties" \
    "$config/android-signing.password"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -f "$path" && ! -L "$path" &&
        "$(file_mode "$path" 2>/dev/null)" == 600 ]] || return 1
    fi
  done
}

skidbladnir_prepare_directories() {
  local home="$1"
  local service_parent

  case "$2" in
  macos) service_parent="$home/Library/LaunchAgents" ;;
  arch | devbox) service_parent="$home/.config/systemd/user" ;;
  *) return 1 ;;
  esac

  dev_server_reconcile_directory "$home/.local" 0755
  dev_server_reconcile_directory "$home/.local/bin" 0755
  dev_server_reconcile_directory "$home/.local/share" 0755
  dev_server_reconcile_directory "$home/.local/share/skidbladnir" 0700
  dev_server_reconcile_directory "$home/.local/share/skidbladnir/artifacts" 0700
  dev_server_reconcile_directory "$home/.local/share/skidbladnir/releases" 0700
  dev_server_reconcile_directory "$home/.local/share/skidbladnir/units" 0700
  dev_server_reconcile_directory "$home/.local/state" 0755
  dev_server_reconcile_directory "$home/.local/state/dev-server" 0700
  dev_server_reconcile_directory "$home/.local/state/dev-server/active" 0700
  dev_server_reconcile_directory "$home/.local/state/skidbladnir" 0700
  dev_server_reconcile_directory "$home/.config" 0755
  dev_server_reconcile_directory "$home/.config/skidbladnir" 0700
  if [[ "$2" == macos ]]; then
    dev_server_reconcile_directory "$home/Library" 0755
  else
    dev_server_reconcile_directory "$home/.config/systemd" 0755
  fi
  dev_server_reconcile_directory "$service_parent" 0755
}

skidbladnir_validate_link() {
  local target="$1"
  local kind="$2"
  local value

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 1
  fi
  [[ -L "$target" ]] || return 2
  value="$(readlink "$target")" || return 2
  case "$kind:$value" in
  generation:releases/v*-????????????????????????????????????????????????????????????????) ;;
  binary:../share/skidbladnir/current/skidbladnir) ;;
  *) return 2 ;;
  esac
  if [[ "$kind" == generation ]]; then
    [[ "$value" =~ ^releases/v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})-[0-9a-f]{64}$ ]] || return 2
  fi
  printf '%s\n' "$value"
}

skidbladnir_validate_protected_paths() {
  local home="$1"
  local share="$home/.local/share/skidbladnir"
  local config="$home/.config/skidbladnir"
  local state="$home/.local/state/dev-server"
  local link path

  for path in \
    "$home/.local" \
    "$home/.local/share" \
    "$share" \
    "$share/artifacts" \
    "$share/releases" \
    "$share/units" \
    "$home/.local/state" \
    "$state" \
    "$state/active" \
    "$home/.config" \
    "$config"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -d "$path" && ! -L "$path" ]] || die "protected Skidbladnir directory is invalid: $path"
    fi
  done
  for link in "$share/current" "$share/previous"; do
    if [[ -e "$link" || -L "$link" ]]; then
      skidbladnir_validate_link "$link" generation >/dev/null ||
        die "protected Skidbladnir link is invalid: $link"
    fi
  done
  for link in "$home/.local/bin/skidbladnir" "$home/.local/bin/skid"; do
    if [[ -e "$link" || -L "$link" ]]; then
      skidbladnir_validate_link "$link" binary >/dev/null ||
        die "protected Skidbladnir link is invalid: $link"
    fi
  done
  for path in \
    "$config/bearer" \
    "$config/machine-handle" \
    "$config/android-signing.p12" \
    "$config/android-signing.properties" \
    "$config/android-signing.password"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -f "$path" && ! -L "$path" ]] || die "protected Skidbladnir credential is invalid: $path"
    fi
  done
}

skidbladnir_validate_active_journals() {
  local home="$1"
  local path status

  for path in \
    "$home/.local/state/dev-server/active/skid.runtime.sha256" \
    "$home/.local/state/dev-server/active/skid.unit.sha256"; do
    if skidbladnir_active_identity "$path" >/dev/null; then
      continue
    else
      status=$?
    fi
    ((status == 1)) || return 1
  done
}

skidbladnir_discard_stage() {
  dev_server_remove_stage "$1" "$2" ||
    die 'could not remove the Skidbladnir staging directory'
}

skidbladnir_archive_members_exact() {
  local archive="$1"
  local members types

  members="$(tar -tzf "$archive" 2>/dev/null | LC_ALL=C sort)" || return 1
  [[ "$members" == $'characters.json\nrelease.json\nskidbladnir' ]] || return 1
  types="$(tar -tvzf "$archive" 2>/dev/null | LC_ALL=C awk '{print substr($1,1,1)}' | LC_ALL=C sort)" || return 1
  [[ "$types" == $'-\n-\n-' ]]
}

# staging alone (spec §4.3), never through skidbladnir_apply; directories exist on every host.
# the assets are copied and rendered first (deployment identity, lib/common.sh):
#   bash -c 'set -euo pipefail
#     cd DEV_SERVER_CHECKOUT; source lib/common.sh; source lib/skidbladnir.sh
#     platform=macos # or arch | devbox
#     assets="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-assets.XXXXXX")"
#     cp -Rp assets "$assets/assets"; dev_server_render_assets "$assets/assets"
#     home="$(dev_server_home)"; share="$home/.local/share/skidbladnir"
#     skidbladnir_prepare_directories "$home" "$platform"
#     dev_server_acquire_lock "$share/.apply.lock" 9 Skidbladnir
#     stage="$(mktemp -d "$share/.apply.stage.XXXXXX")"
#     read -r version source_sha url archive_sha manifest_platform <<<"$(skidbladnir_release_values "$platform" | tr "\t" " ")"
#     skidbladnir_prepare_artifact "$stage" "$version" "$source_sha" "$url" "$archive_sha" "$manifest_platform" "$share/artifacts/$archive_sha"
#     "$share/artifacts/$archive_sha/skidbladnir" validate-host-config --host-config="$(skidbladnir_host_config_source "$platform")"
#     dev_server_remove_stage "$share" "$stage"; rm -R "$assets"
#     exec 9>&-'
skidbladnir_prepare_artifact() {
  local stage="$1"
  local version="$2"
  local source_sha="$3"
  local url="$4"
  local archive_sha="$5"
  local manifest_platform="$6"
  local artifact="$7"
  local archive="$stage/archive.tar.gz"
  local payload="$stage/artifact"
  local identity framed

  # The directory key records archive admission. The receipt catches accidental
  # changes to its extracted files without downloading or extracting again.
  if [[ -e "$artifact" || -L "$artifact" ]]; then
    [[ -d "$artifact" && ! -L "$artifact" ]] || return 6
    identity="$(skidbladnir_active_identity "$artifact/identity.sha256")" || return 6
    [[ "$(skidbladnir_payload_hashes "$artifact" | dev_server_sha256_stream)" == "$identity" ]] || return 6
    [[ "$(file_mode "$artifact/skidbladnir")" == 755 &&
    "$(file_mode "$artifact/characters.json")" == 644 &&
    "$(file_mode "$artifact/release.json")" == 644 ]] || return 6
    skidbladnir_release_manifest_matches "$artifact/release.json" \
      "$manifest_platform" "$source_sha" "$version" || return 4
    return 0
  fi
  dev_server_download "$url" "$archive" || return 1
  [[ "$(dev_server_sha256 "$archive")" == "$archive_sha" ]] || return 2
  skidbladnir_archive_members_exact "$archive" || return 3
  mkdir -m 0700 "$payload" || return 1
  tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$payload" \
    skidbladnir characters.json release.json || return 3
  [[ -f "$payload/skidbladnir" && ! -L "$payload/skidbladnir" ]] || return 3
  [[ -f "$payload/characters.json" && ! -L "$payload/characters.json" ]] || return 3
  [[ -f "$payload/release.json" && ! -L "$payload/release.json" ]] || return 3
  chmod 0755 "$payload/skidbladnir" || return 1
  chmod 0644 "$payload/characters.json" "$payload/release.json" || return 1
  skidbladnir_release_manifest_matches "$payload/release.json" \
    "$manifest_platform" "$source_sha" "$version" || return 4
  framed="$("$payload/skidbladnir" version && printf .)" || return 5
  identity="${framed%$'\n.'}"
  [[ "$framed" == "$identity"$'\n.' && "$identity" == "$version $source_sha" ]] || return 5
  skidbladnir_payload_hashes "$payload" | dev_server_sha256_stream >"$payload/identity.sha256" || return 1
  chmod 0600 "$payload/identity.sha256" || return 1
  mv "$payload" "$artifact"
}

skidbladnir_generation_exact() {
  local desired="$1"
  local installed="$2"
  local host_config="$3"

  skidbladnir_generation_owned "$installed" || return 1
  cmp -s "$desired/skidbladnir" "$installed/skidbladnir" &&
    cmp -s "$desired/characters.json" "$installed/characters.json" &&
    cmp -s "$desired/release.json" "$installed/release.json" &&
    cmp -s "$host_config" "$installed/host-config.json"
}

skidbladnir_payload_hashes() {
  local payload="$1"
  local name digest

  for name in skidbladnir characters.json release.json; do
    digest="$(dev_server_sha256 "$payload/$name")" || return 1
    printf '%s\0%s\n' "$name" "$digest"
  done
}

skidbladnir_runtime_identity() {
  local generation="$1"
  local host_config="${2:-$generation/host-config.json}"
  local digest

  digest="$(dev_server_sha256 "$host_config")" || return 1
  {
    skidbladnir_payload_hashes "$generation" || return 1
    printf 'host-config.json\0%s\n' "$digest"
  } | dev_server_sha256_stream
}

skidbladnir_unit_source() {
  case "$1" in
  macos) printf '%s/skidbladnir/dev.niels.skidbladnir.plist\n' "$(dev_server_assets_dir)" ;;
  arch | devbox) printf '%s/skidbladnir/skidbladnir.service\n' "$(dev_server_assets_dir)" ;;
  *) return 1 ;;
  esac
}

skidbladnir_unit_target() {
  case "$1" in
  macos) printf '%s/Library/LaunchAgents/%s.skidbladnir.plist\n' "$2" "$dev_server_fleet_label_prefix" ;;
  arch | devbox) printf '%s/.config/systemd/user/skidbladnir.service\n' "$2" ;;
  *) return 1 ;;
  esac
}

skidbladnir_unit_identity() {
  local platform="$1"
  local launcher unit
  launcher="$(dev_server_assets_dir)/skidbladnir/skidbladnir-launch"
  unit="$(skidbladnir_unit_source "$platform")" || return 1
  skidbladnir_unit_files_identity "$launcher" "$unit"
}

skidbladnir_unit_files_identity() {
  local launcher="$1"
  local unit="$2"

  [[ -f "$launcher" && ! -L "$launcher" &&
    -f "$unit" && ! -L "$unit" ]] || return 1
  printf 'launcher\0%s\nunit\0%s\n' \
    "$(dev_server_sha256 "$launcher")" "$(dev_server_sha256 "$unit")" |
    dev_server_sha256_stream
}

skidbladnir_unit_generation_owned() {
  local path="$1"
  local entry name
  local entries=0

  name="$(basename "$path")"
  [[ "$name" =~ ^[0-9a-f]{64}$ && -d "$path" && ! -L "$path" ]] || return 1
  while IFS= read -r -d '' entry; do
    case "$(basename "$entry")" in
    launcher | unit) ;;
    *) return 1 ;;
    esac
    entries=$((entries + 1))
  done < <(find "$path" -mindepth 1 -maxdepth 1 -print0)
  ((entries == 2)) || return 1
  [[ -f "$path/launcher" && ! -L "$path/launcher" &&
    -f "$path/unit" && ! -L "$path/unit" ]] || return 1
  [[ "$(file_mode "$path/launcher" 2>/dev/null)" == 755 &&
  "$(file_mode "$path/unit" 2>/dev/null)" == 644 ]] || return 1
  [[ "$(skidbladnir_unit_files_identity "$path/launcher" "$path/unit")" == "$name" ]]
}

skidbladnir_prepare_unit_generation() {
  local platform="$1"
  local stage="$2"
  local units="$3"
  local identity="$4"
  local candidate="$stage/unit-generation"
  local installed="$units/$identity"
  local launcher unit

  launcher="$(dev_server_assets_dir)/skidbladnir/skidbladnir-launch"
  unit="$(skidbladnir_unit_source "$platform")" || return 1
  if [[ -e "$installed" || -L "$installed" ]]; then
    skidbladnir_unit_generation_owned "$installed" || return 1
    cmp -s "$launcher" "$installed/launcher" && cmp -s "$unit" "$installed/unit"
    return
  fi
  mkdir -m 0700 "$candidate" || return 1
  install -m 0755 "$launcher" "$candidate/launcher" || return 1
  install -m 0644 "$unit" "$candidate/unit" || return 1
  [[ "$(skidbladnir_unit_files_identity "$candidate/launcher" "$candidate/unit")" == "$identity" ]] ||
    return 1
  mv "$candidate" "$installed" || return 1
  skidbladnir_unit_generation_owned "$installed"
}

skidbladnir_promote_secret() {
  python3 - "$1" "$2" <<'PY'
import os
import sys

# A hard-link promotion is same-filesystem and fails rather than replacing a
# credential created concurrently. Unlinking the staging name leaves one file.
os.link(sys.argv[1], sys.argv[2], follow_symlinks=False)
os.unlink(sys.argv[1])
PY
}

skidbladnir_atomic_symlink() {
  local target="$1"
  local relative="$2"
  local kind="$3"

  case "$kind:$relative" in
  generation:releases/v*-????????????????????????????????????????????????????????????????) ;;
  binary:../share/skidbladnir/current/skidbladnir) ;;
  *) return 1 ;;
  esac
  dev_server_atomic_symlink "$target" "$relative"
}

skidbladnir_mint_secret() (
  local binary="$1"
  local target="$2"
  local kind="$3"
  local pattern="$4"
  local parent name staging='' temporary

  parent="$(dirname "$target")"
  name="$(basename "$target")"
  skidbladnir_secret_stage_cleanup() {
    if [[ -n "$staging" && "$(dirname "$staging")" == "$parent" &&
    "$(basename "$staging")" =~ ^\.${name}\.dev-server\.[A-Za-z0-9]{6}$ &&
    -d "$staging" && ! -L "$staging" ]]; then
      rm -R -- "$staging"
    fi
  }
  trap skidbladnir_secret_stage_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if [[ -e "$target" || -L "$target" ]]; then
    skidbladnir_secret_valid "$target" "$pattern"
    return
  fi
  staging="$(mktemp -d "$parent/.$name.dev-server.XXXXXX")" || return 1
  chmod 0700 "$staging" || return 1
  temporary="$staging/value"
  case "$kind" in
  machine) "$binary" machine init --file="$temporary" >/dev/null || {
    return 1
  } ;;
  bearer) "$binary" bearer mint --file="$temporary" >/dev/null || {
    return 1
  } ;;
  *) return 1 ;;
  esac
  chmod 0600 "$temporary" || {
    return 1
  }
  skidbladnir_secret_valid "$temporary" "$pattern" || {
    return 1
  }
  if ! skidbladnir_promote_secret "$temporary" "$target"; then
    skidbladnir_secret_valid "$target" "$pattern"
    return
  fi
  skidbladnir_secret_valid "$target" "$pattern"
)

skidbladnir_active_identity() {
  local path="$1"
  local value framed

  if [[ ! -e "$path" && ! -L "$path" ]]; then
    return 1
  fi
  [[ -f "$path" && ! -L "$path" && "$(file_mode "$path" 2>/dev/null)" == 600 ]] || return 2
  value="$(cat "$path")" || return 2
  framed="$(cat "$path" && printf .)" || return 2
  [[ "$framed" == "$value"$'\n.' && "$value" =~ ^[0-9a-f]{64}$ ]] || return 2
  printf '%s\n' "$value"
}

skidbladnir_service_state() {
  case "$1" in
  arch | devbox) dev_server_service_state "$1" skidbladnir.service ;;
  macos) dev_server_service_state "$1" "$dev_server_fleet_label_prefix.skidbladnir" ;;
  *) return 2 ;;
  esac
}

skidbladnir_service_active() {
  local state

  state="$(skidbladnir_service_state "$1")" || return 2
  [[ "$state" == active ]]
}

skidbladnir_wait_for_active() {
  local platform="$1"
  local attempt observation

  for attempt in 1 2 3 4 5; do
    if skidbladnir_service_active "$platform"; then
      return 0
    else
      observation=$?
    fi
    ((observation == 1)) || return 2
    ((attempt == 5)) || sleep 1
  done
  return 1
}

skidbladnir_service_enabled() {
  case "$1" in
  arch | devbox) dev_server_service_enabled "$1" skidbladnir.service ;;
  macos) dev_server_service_enabled "$1" "$dev_server_fleet_label_prefix.skidbladnir" ;;
  *) return 1 ;;
  esac
}

skidbladnir_activate_service() {
  local platform="$1"
  local home="$2"
  local was_active="$3"
  local needs_activation="$4"
  local unit_changed="$5"
  local target domain label enabled_status state

  skidbladnir_activation_status=''
  skidbladnir_enablement_changed=0
  case "$platform" in
  arch | devbox)
    if ((unit_changed)); then
      systemctl --user daemon-reload || return 1
    fi
    if skidbladnir_service_enabled "$platform"; then
      enabled_status=0
    else
      enabled_status=$?
    fi
    if ((enabled_status != 0)); then
      ((enabled_status == 1)) || return 1
      systemctl --user enable skidbladnir.service || return 1
      skidbladnir_enablement_changed=1
    fi
    if ((was_active)); then
      if ((needs_activation)); then
        systemctl --user restart skidbladnir.service || return 1
        skidbladnir_activation_status=RESTARTED
      fi
    else
      systemctl --user start skidbladnir.service || return 1
      skidbladnir_activation_status=STARTED
    fi
    ;;
  macos)
    target="$(skidbladnir_unit_target "$platform" "$home")"
    domain="gui/$(id -u)"
    label="$dev_server_fleet_label_prefix.skidbladnir"
    if skidbladnir_service_enabled "$platform"; then
      enabled_status=0
    else
      enabled_status=$?
    fi
    if ((enabled_status != 0)); then
      ((enabled_status == 1)) || return 1
      launchctl enable "$domain/$label" || return 1
      skidbladnir_enablement_changed=1
    fi
    if ((was_active && !needs_activation)); then
      return 0
    fi
    # launchd retains the loaded definition even while its process is stopped.
    state="$(skidbladnir_service_state "$platform")" || return 1
    if [[ "$state" != absent ]] && ((unit_changed)); then
      skidbladnir_stop_service "$platform" || return 1
      state=absent
    fi
    if [[ "$state" == absent ]]; then
      launchctl bootstrap "$domain" "$target" || return 1
    else
      launchctl kickstart -k "$domain/$label" || return 1
    fi
    if ((was_active)); then
      skidbladnir_activation_status=RESTARTED
    else
      skidbladnir_activation_status=STARTED
    fi
    ;;
  *) return 1 ;;
  esac
}

# 0 once the supervisor has torn the service down or when it was already absent.
skidbladnir_stop_service() {
  case "$1" in
  macos) dev_server_stop_service macos "$dev_server_fleet_label_prefix.skidbladnir" ;;
  arch | devbox) dev_server_stop_service "$1" skidbladnir.service ;;
  *) return 1 ;;
  esac
}

skidbladnir_running_binary_matches() {
  local platform="$1"
  local home="$2"
  local runtime_ref="${3:-current}"
  local expected
  local pid executable

  case "$runtime_ref" in
  current | releases/v*-????????????????????????????????????????????????????????????????) ;;
  *) return 1 ;;
  esac
  expected="$home/.local/share/skidbladnir/$runtime_ref/skidbladnir"
  expected="$(cd "$(dirname "$expected")" && pwd -P)/$(basename "$expected")" || return 1

  case "$platform" in
  arch | devbox)
    pid="$(dev_server_service_main_pid "$platform" skidbladnir.service)" || return 1
    executable="$(readlink "/proc/$pid/exe" 2>/dev/null)" || return 1
    [[ "$executable" == "$expected" && -f "$executable" && ! -L "$executable" ]] || return 1
    ;;
  macos)
    pid="$(dev_server_service_main_pid "$platform" "$dev_server_fleet_label_prefix.skidbladnir")" || return 1
    /usr/sbin/lsof -a -p "$pid" -d txt -Fn 2>/dev/null |
      grep -Fqx "n$expected" || return 1
    ;;
  *) return 1 ;;
  esac
}

skidbladnir_authenticated_health() (
  set +x
  local home="$1"
  local expected_version="$2"
  local platform="${3:-}"
  local runtime_ref="${4:-current}"
  local config="$home/.config/skidbladnir"
  local response bytes observed_version attempt

  skidbladnir_secret_valid "$config/machine-handle" '^mh-[0-9a-f]{32}$' || return 1
  skidbladnir_secret_valid "$config/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || return 1
  observed_version="$(jq -er '.version' "$home/.local/share/skidbladnir/$runtime_ref/release.json")" || return 1
  [[ "$observed_version" == "$expected_version" ]] || return 1
  for attempt in 1 2 3 4 5; do
    response="$({
      printf 'silent\nshow-error\nfail\nconnect-timeout = 1\nmax-time = 2\nmax-filesize = 65536\n'
      printf 'header = "Authorization: Bearer %s"\n' "$(cat "$config/bearer")"
      printf 'header = "Skidbladnir-Machine: %s"\n' "$(cat "$config/machine-handle")"
      printf 'url = "http://127.0.0.1:%s/v1/pressure"\n' "$dev_server_gateway_port"
    } | curl -q --noproxy '*' --config - 2>/dev/null || true)"
    bytes="$(LC_ALL=C printf '%s' "$response" | wc -c | tr -d '[:space:]')"
    if [[ "$bytes" =~ ^[1-9][0-9]*$ && "$bytes" -le 65536 ]] &&
      printf '%s' "$response" | jq -e '
        type == "object" and
        (.current | type == "object") and
        (.history | type == "array") and
        (.unsupported | type == "array")
      ' >/dev/null 2>&1 &&
      { [[ -z "$platform" ]] || skidbladnir_running_binary_matches "$platform" "$home" "$runtime_ref"; }; then
      return 0
    fi
    ((attempt == 5)) || sleep 1
  done
  return 1
)

skidbladnir_restore_runtime() {
  local platform="$1"
  local home="$2"
  local stage="$3"
  local prior_current="$4"
  local prior_previous="$5"
  local prior_version="$6"
  local unit_target="$7"
  local was_enabled="$8"
  local active_unit="$9"
  local share="$home/.local/share/skidbladnir"
  local unit_generation

  if [[ -z "$prior_current" && "$platform" != macos && "$was_enabled" == 0 ]]; then
    # systemd needs the unit file to remove its enablement links.
    systemctl --user disable skidbladnir.service >/dev/null 2>&1 || return 1
  fi

  if [[ -n "$active_unit" ]]; then
    unit_generation="$share/units/$active_unit"
    skidbladnir_unit_generation_owned "$unit_generation" || return 1
    atomic_install_file "$unit_generation/launcher" \
      "$home/.local/bin/skidbladnir-launch" 0755 || return 1
    atomic_install_file "$unit_generation/unit" "$unit_target" 0644 || return 1
  elif [[ -z "$prior_current" ]]; then
    for unit_generation in "$home/.local/bin/skidbladnir-launch" "$unit_target"; do
      if [[ -e "$unit_generation" || -L "$unit_generation" ]]; then
        [[ -f "$unit_generation" && ! -L "$unit_generation" ]] || return 1
        rm -f -- "$unit_generation" || return 1
      fi
    done
  else
    dev_server_restore_file "$home/.local/bin/skidbladnir-launch" \
      "$stage/launcher-backup" 0755 || return 1
    dev_server_restore_file "$unit_target" "$stage/unit-backup" 0644 || return 1
  fi
  if [[ -n "$prior_current" ]]; then
    skidbladnir_atomic_symlink "$share/current" "$prior_current" generation || return 1
  else
    dev_server_remove_link "$share/current" || return 1
  fi
  if [[ -n "$prior_previous" ]]; then
    skidbladnir_atomic_symlink "$share/previous" "$prior_previous" generation || return 1
  else
    dev_server_remove_link "$share/previous" || return 1
  fi
  if [[ -z "$prior_current" ]]; then
    dev_server_remove_link "$home/.local/bin/skidbladnir" || return 1
    dev_server_remove_link "$home/.local/bin/skid" || return 1
  fi

  skidbladnir_stop_service "$platform" || return 1
  if [[ -z "$prior_current" ]]; then
    if [[ "$platform" != macos ]]; then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
  else
    if [[ "$platform" == macos ]]; then
      launchctl bootstrap "gui/$(id -u)" "$unit_target" || return 1
    else
      systemctl --user daemon-reload || return 1
      systemctl --user restart skidbladnir.service || return 1
    fi
    skidbladnir_authenticated_health "$home" "$prior_version" "$platform" || return 1
  fi

  # A disabled service can still be running. Restore that durable preference
  # only after the prior runtime has been bootstrapped and verified.
  if [[ "$was_enabled" == 0 ]]; then
    if [[ "$platform" == macos ]]; then
      launchctl disable "gui/$(id -u)/$dev_server_fleet_label_prefix.skidbladnir" >/dev/null 2>&1 || return 1
    elif [[ -n "$prior_current" ]]; then
      systemctl --user disable skidbladnir.service >/dev/null 2>&1 || return 1
    fi
  fi
}

skidbladnir_install_runtime_files() {
  local platform="$1"
  local home="$2"
  local unit_source unit_target launcher_source

  unit_source="$(skidbladnir_unit_source "$platform")" || return 1
  unit_target="$(skidbladnir_unit_target "$platform" "$home")" || return 1
  launcher_source="$(dev_server_assets_dir)/skidbladnir/skidbladnir-launch"
  skidbladnir_unit_changed=0
  skidbladnir_command_installed=0

  atomic_install_file "$launcher_source" "$home/.local/bin/skidbladnir-launch" 0755 || return 1
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || skidbladnir_unit_changed=1
  atomic_install_file "$unit_source" "$unit_target" 0644 || return 1
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || skidbladnir_unit_changed=1
  [[ -L "$home/.local/bin/skidbladnir" ]] || skidbladnir_command_installed=1
  skidbladnir_atomic_symlink "$home/.local/bin/skidbladnir" \
    '../share/skidbladnir/current/skidbladnir' binary || return 1
}

skidbladnir_install_integration_file() {
  atomic_install_file "$1" "$2" "$3" || return 1
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || skidbladnir_integration_changed=1
}

skidbladnir_install_integrations() {
  local platform="$1"
  local home="$2"
  local hooks notifier_source context directory plugin source target mode

  hooks="$(skidbladnir_agent_hooks_source "$platform")" || return 1
  notifier_source="$(dev_server_assets_dir)/skidbladnir/skid-notify"
  skidbladnir_integration_changed=0
  dev_server_directory_changed=0
  skidbladnir_install_integration_file "$notifier_source" "$home/.local/bin/skid-notify" 0755 || return 1

  for context in personal work work2; do
    case "$context" in
    personal) directory="$home/.codex" ;;
    *) directory="$home/.codex-$context" ;;
    esac
    dev_server_reconcile_directory "$directory" 0700
    skidbladnir_install_integration_file "$hooks" "$directory/hooks.json" 0600 || return 1
  done
  plugin="$home/.local/share/skidbladnir/claude-agent-identity"
  dev_server_reconcile_directory "$plugin" 0755
  dev_server_reconcile_directory "$plugin/.claude-plugin" 0755
  dev_server_reconcile_directory "$plugin/hooks" 0755
  dev_server_reconcile_directory "$plugin/bin" 0755
  while read -r source target mode; do
    skidbladnir_install_integration_file \
      "$(dev_server_assets_dir)/skidbladnir/claude-agent-identity/$source" \
      "$plugin/$target" "$mode" || return 1
  done <<'FILES'
.claude-plugin/plugin.json .claude-plugin/plugin.json 0644
hooks/hooks.json hooks/hooks.json 0644
bin/agent-hook bin/agent-hook 0755
FILES
  ((dev_server_directory_changed == 0)) || skidbladnir_integration_changed=1
  if ((skidbladnir_integration_changed)); then
    render_result CHANGED skid.integration 'identity hooks and terminal bell notifier installed'
  fi
}

skidbladnir_tailscale_cli() {
  if declare -F packages_macos_tailscale_cli >/dev/null; then
    packages_macos_tailscale_cli
  else
    command -v tailscale
  fi
}

skidbladnir_tailscale_dns_name() {
  python3 -c '
import json, re, sys

def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result

value = json.load(sys.stdin, object_pairs_hook=unique)
dns = value.get("Self", {}).get("DNSName") if isinstance(value, dict) else None
if (value.get("BackendState") != "Running" or not isinstance(dns, str) or
        not re.fullmatch(r"[a-z0-9][a-z0-9.-]*[a-z0-9]\.", dns)):
    raise SystemExit(1)
print(dns[:-1])
'
}

skidbladnir_serve_classification() {
  local hostname="$1"
  python3 -c '
import json, sys

def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key")
        result[key] = value
    return result

value = json.load(sys.stdin, object_pairs_hook=unique)
if not isinstance(value, dict):
    raise SystemExit(1)
tcp = value.get("TCP") or {}
web = value.get("Web") or {}
funnel = value.get("AllowFunnel") or {}
if not all(isinstance(item, dict) for item in (tcp, web, funnel)):
    raise SystemExit(1)
key = sys.argv[1] + ":8443"
if any(name.endswith(":8443") and enabled is True
       for name, enabled in funnel.items()):
    print("public")
elif (tcp.get("8443") == {"HTTPS": True} and
      [(name, entry) for name, entry in web.items() if name.endswith(":8443")] == [
          (key, {"Handlers": {"/v1": {"Proxy": "http://127.0.0.1:" + sys.argv[2] + "/v1"}}})
      ] and funnel.get(key, False) is False):
    print("desired")
elif not any(name.endswith(":8443") for name in web) and tcp.get("8443") is None:
    print("empty")
else:
    print("stale")
' "$hostname" "$dev_server_gateway_port"
}

skidbladnir_serve_action() {
  render_result ACTION tailscale.serve \
    "remove the stale HTTPS 8443 mapping with 'tailscale serve --https=8443 off', then rerun apply"
}

skidbladnir_observe_serve() {
  local status

  skidbladnir_serve_cli="$(skidbladnir_tailscale_cli 2>/dev/null || true)"
  skidbladnir_serve_hostname=''
  skidbladnir_serve_json=''
  skidbladnir_serve_state=''
  if [[ -z "$skidbladnir_serve_cli" ]]; then
    skidbladnir_serve_state=missing
    return 0
  fi
  status="$(TAILSCALE_BE_CLI=1 "$skidbladnir_serve_cli" status --json 2>/dev/null || true)"
  ((${#status} <= 65536)) || return 1
  skidbladnir_serve_hostname="$(
    printf '%s' "$status" | skidbladnir_tailscale_dns_name 2>/dev/null || true
  )"
  if [[ -z "$skidbladnir_serve_hostname" ]]; then
    skidbladnir_serve_state=signed-out
    return 0
  fi
  skidbladnir_serve_json="$(
    TAILSCALE_BE_CLI=1 "$skidbladnir_serve_cli" serve status --json 2>/dev/null || true
  )"
  [[ -n "$skidbladnir_serve_json" ]] || return 1
  ((${#skidbladnir_serve_json} <= 65536)) || return 1
  skidbladnir_serve_state="$(printf '%s' "$skidbladnir_serve_json" |
    skidbladnir_serve_classification "$skidbladnir_serve_hostname")" || return 1
}

skidbladnir_preflight_serve() {
  skidbladnir_observe_serve || return 1
  case "$skidbladnir_serve_state" in
  desired | empty) return 0 ;;
  missing)
    render_result ACTION tailscale.serve 'install and sign in to Tailscale, then rerun apply'
    return 2
    ;;
  signed-out)
    render_result ACTION tailscale.serve 'sign in to Tailscale, then rerun apply'
    return 2
    ;;
  stale)
    skidbladnir_serve_action
    return 2
    ;;
  public) return 3 ;;
  *) return 1 ;;
  esac
}

skidbladnir_reconcile_serve() {
  local post

  skidbladnir_observe_serve || return 1
  case "$skidbladnir_serve_state" in
  desired) return 0 ;;
  missing)
    render_result ACTION tailscale.serve 'install and sign in to Tailscale, then rerun apply'
    return 0
    ;;
  signed-out)
    render_result ACTION tailscale.serve 'sign in to Tailscale, then rerun apply'
    return 0
    ;;
  stale)
    skidbladnir_serve_action
    return 0
    ;;
  public) return 3 ;;
  empty) ;;
  *) return 1 ;;
  esac
  TAILSCALE_BE_CLI=1 "$skidbladnir_serve_cli" serve --bg --yes --https=8443 --set-path=/v1 \
    "http://127.0.0.1:$dev_server_gateway_port/v1" >/dev/null || return 1
  post="$(TAILSCALE_BE_CLI=1 "$skidbladnir_serve_cli" serve status --json 2>/dev/null || true)"
  ((${#post} <= 65536)) || return 1
  [[ "$(printf '%s' "$post" |
    skidbladnir_serve_classification "$skidbladnir_serve_hostname")" == desired ]] || return 1
  render_result CHANGED tailscale.serve 'private /v1 mapping installed'
}

# ingress is host-level: one node has one tailscale :8443 mapping, so the host
# entry points (workstation, the devbox role) run it around skidbladnir_apply;
# a second deployment on the same node never calls it. preflight returns 0 to
# proceed or 2 after rendering an ACTION, with nothing to apply.
skidbladnir_ingress_preflight() {
  local status=0

  skidbladnir_preflight_serve || status=$?
  case "$status" in
  0 | 2) return "$status" ;;
  3) die 'public Tailscale exposure is enabled for Skidbladnir HTTPS 8443' ;;
  *) die 'could not inspect the private Skidbladnir Serve boundary' ;;
  esac
}

skidbladnir_ingress_apply() {
  local status=0

  skidbladnir_reconcile_serve || status=$?
  case "$status" in
  0) ;;
  3) die 'public Tailscale exposure is enabled for Skidbladnir HTTPS 8443' ;;
  *) die 'could not reconcile the private Skidbladnir Serve mapping' ;;
  esac
}

skidbladnir_generation_owned() {
  local path="$1"
  local name entries
  name="$(basename "$path")"
  [[ "$name" =~ ^v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})-[0-9a-f]{64}$ ]] || return 1
  [[ -d "$path" && ! -L "$path" ]] || return 1
  entries="$(find "$path" -mindepth 1 -maxdepth 1 -print | sed "s#^$path/##" | LC_ALL=C sort)" || return 1
  [[ "$entries" == $'characters.json\nhost-config.json\nrelease.json\nskidbladnir' ]] || return 1
  [[ -f "$path/skidbladnir" && ! -L "$path/skidbladnir" &&
    -f "$path/characters.json" && ! -L "$path/characters.json" &&
    -f "$path/release.json" && ! -L "$path/release.json" &&
    -f "$path/host-config.json" && ! -L "$path/host-config.json" ]] || return 1
  [[ "$(file_mode "$path/skidbladnir" 2>/dev/null)" == 755 &&
  "$(file_mode "$path/characters.json" 2>/dev/null)" == 644 &&
  "$(file_mode "$path/release.json" 2>/dev/null)" == 644 &&
  "$(file_mode "$path/host-config.json" 2>/dev/null)" == 600 ]]
}

skidbladnir_validate_installed_generations() {
  local home="$1"
  local share="$home/.local/share/skidbladnir"
  local releases="$share/releases"
  local path link relative
  while IFS= read -r -d '' path; do
    skidbladnir_generation_owned "$path" || return 1
  done < <(find "$releases" -mindepth 1 -maxdepth 1 -print0)
  for link in "$share/current" "$share/previous"; do
    if [[ -L "$link" ]]; then
      relative="$(readlink "$link")" || return 1
      skidbladnir_generation_owned "$share/$relative" || return 1
    fi
  done
}

skidbladnir_validate_installed_unit_generations() {
  local home="$1"
  local units="$home/.local/share/skidbladnir/units"
  local path

  while IFS= read -r -d '' path; do
    skidbladnir_unit_generation_owned "$path" || return 1
  done < <(find "$units" -mindepth 1 -maxdepth 1 -print0)
}

skidbladnir_retain_generations() {
  local home="$1"
  local releases="$home/.local/share/skidbladnir/releases"
  local current previous path relative

  current="$(readlink "$home/.local/share/skidbladnir/current")" || return 1
  previous=''
  if [[ -L "$home/.local/share/skidbladnir/previous" ]]; then
    previous="$(readlink "$home/.local/share/skidbladnir/previous")" || return 1
  fi
  while IFS= read -r -d '' path; do
    relative="releases/$(basename "$path")"
    if [[ "$relative" == "$current" || "$relative" == "$previous" ]]; then
      continue
    fi
    skidbladnir_generation_owned "$path" || return 1
    rm -R -- "$path" || return 1
  done < <(find "$releases" -mindepth 1 -maxdepth 1 -print0)
}

skidbladnir_retain_unit_generations() {
  local home="$1"
  local desired="$2"
  local units="$home/.local/share/skidbladnir/units"
  local path

  [[ "$desired" =~ ^[0-9a-f]{64}$ ]] || return 1
  while IFS= read -r -d '' path; do
    [[ "$(basename "$path")" == "$desired" ]] && continue
    skidbladnir_unit_generation_owned "$path" || return 1
    rm -R -- "$path" || return 1
  done < <(find "$units" -mindepth 1 -maxdepth 1 -print0)
}

skidbladnir_retain_artifact() {
  local desired="$1"
  local path name entries owned

  # Rollback generations already contain their complete payload. Keep only the
  # desired cache; leave unrelated files and directories alone.
  for path in "$(dirname "$desired")"/*; do
    [[ "$path" != "$desired" && -d "$path" && ! -L "$path" ]] || continue
    name="${path##*/}"
    [[ "$name" =~ ^[0-9a-f]{64}$ ]] || continue
    entries="$(find "$path" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)" || return 1
    [[ "$entries" == $'characters.json\nidentity.sha256\nrelease.json\nskidbladnir' ]] || continue
    owned=1
    for name in skidbladnir characters.json release.json identity.sha256; do
      [[ -f "$path/$name" && ! -L "$path/$name" ]] || owned=0
    done
    ((owned)) || continue
    skidbladnir_active_identity "$path/identity.sha256" >/dev/null || continue
    rm -R -- "$path" || return 1
  done
}

skidbladnir_apply() {
  local platform="$1"
  local home share releases units config host_config pin_line version source_sha url archive_sha manifest_platform
  local stage artifact generation_name generation prior_current='' prior_previous='' prior_version=''
  local rollback_current='' rollback_previous='' rollback_version=''
  local current_identity='' previous_identity='' previous_version='' verified_runtime=''
  local unit_target runtime_identity unit_identity active_runtime='' active_unit=''
  local runtime_state unit_state was_active=0 was_enabled=0 needs_activation=0
  local needs_unit_reload=0
  local preparation_status=0 credentials_installed=0 enablement_observation=0
  local service_observation=0 activation_failed=0
  local pointer_changed=0
  local saved_hup saved_int saved_term

  case "$platform" in
  macos) ;;
  arch | devbox)
    [[ "$dev_server_fleet_label_prefix" == dev.niels && "$dev_server_gateway_port" == 7341 ]] ||
      die 'deployment identity on arch and devbox is the systemd user account'
    ;;
  *) die "unsupported Skidbladnir platform: $platform" ;;
  esac
  require_cmd curl jq tar python3
  skidbladnir_validate_declared_inputs "$platform"
  pin_line="$(skidbladnir_release_values "$platform")" || die 'Skidbladnir release pin is invalid'
  IFS=$'\t' read -r version source_sha url archive_sha manifest_platform <<<"$pin_line"
  host_config="$(skidbladnir_host_config_source "$platform")"

  home="$(dev_server_home)"
  share="$home/.local/share/skidbladnir"
  releases="$share/releases"
  units="$share/units"
  config="$home/.config/skidbladnir"
  skidbladnir_validate_protected_paths "$home"
  if skidbladnir_service_active "$platform"; then
    was_active=1
  else
    service_observation=$?
    ((service_observation == 1)) ||
      die 'could not observe Skidbladnir service activity'
  fi
  if skidbladnir_service_enabled "$platform"; then
    was_enabled=1
  else
    enablement_observation=$?
    ((enablement_observation == 1)) ||
      die 'could not observe Skidbladnir service enablement'
  fi
  dev_server_directory_changed=0
  skidbladnir_prepare_directories "$home" "$platform"
  if ((dev_server_directory_changed)); then
    render_result CHANGED skidbladnir.directories 'private directory topology installed'
  fi
  dev_server_acquire_lock "$share/.apply.lock" 9 Skidbladnir
  skidbladnir_validate_local_state "$home"
  dev_server_remove_stale_stages "$share" ||
    die 'stale Skidbladnir staging state is invalid'
  skidbladnir_validate_installed_generations "$home" ||
    die 'installed Skidbladnir generation topology is invalid'
  skidbladnir_validate_installed_unit_generations "$home" ||
    die 'installed Skidbladnir unit generation topology is invalid'

  stage="$(mktemp -d "$share/.apply.stage.XXXXXX")" || die 'could not create Skidbladnir staging directory'
  chmod 0700 "$stage" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not secure the Skidbladnir staging directory'
  }
  saved_hup="$(trap -p HUP)"
  saved_int="$(trap -p INT)"
  saved_term="$(trap -p TERM)"
  trap 'dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true; exit 129' HUP
  trap 'dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true; exit 130' INT
  trap 'dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true; exit 143' TERM
  artifact="$share/artifacts/$archive_sha"
  if skidbladnir_prepare_artifact "$stage" "$version" "$source_sha" \
    "$url" "$archive_sha" "$manifest_platform" "$artifact"; then
    preparation_status=0
  else
    preparation_status=$?
  fi
  if ((preparation_status != 0)); then
    skidbladnir_discard_stage "$share" "$stage"
    case "$preparation_status" in
    2) die 'Skidbladnir archive checksum differs from the release pin' ;;
    3) die 'Skidbladnir archive members are invalid' ;;
    4) die 'Skidbladnir release manifest differs from the release pin' ;;
    5) die 'Skidbladnir binary identity differs from the release pin' ;;
    6) die "Skidbladnir cached artifact is invalid: $artifact" ;;
    *) die 'could not prepare the Skidbladnir release' ;;
    esac
  fi

  # product schema belongs to the admitted binary; the shell kept only deployment facts.
  "$artifact/skidbladnir" validate-host-config --host-config="$host_config" >/dev/null || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir host config is invalid'
  }

  runtime_identity="$(skidbladnir_runtime_identity "$artifact" "$host_config")" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir runtime identity is invalid'
  }
  generation_name="$version-$runtime_identity"
  generation="$releases/$generation_name"
  if [[ -e "$generation" || -L "$generation" ]]; then
    if ! skidbladnir_generation_exact "$artifact" "$generation" "$host_config"; then
      skidbladnir_discard_stage "$share" "$stage"
      die 'immutable Skidbladnir generation differs from its admitted release'
    fi
  else
    mkdir -m 0700 "$stage/generation" &&
      install -m 0755 "$artifact/skidbladnir" "$stage/generation/skidbladnir" &&
      install -m 0644 "$artifact/characters.json" "$artifact/release.json" "$stage/generation/" &&
      install -m 0600 "$host_config" "$stage/generation/host-config.json" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'could not stage the Skidbladnir generation'
    }
    mv "$stage/generation" "$generation" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'could not promote the Skidbladnir generation'
    }
    render_result INSTALLED skid.runtime "$generation_name"
  fi

  if [[ -L "$share/current" ]]; then
    prior_current="$(readlink "$share/current")"
    prior_version="$(jq -er '.version' "$share/current/release.json")" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'current Skidbladnir generation manifest is invalid'
    }
  fi
  if [[ -L "$share/previous" ]]; then
    prior_previous="$(readlink "$share/previous")"
  fi
  unit_target="$(skidbladnir_unit_target "$platform" "$home")"
  dev_server_snapshot_file "$home/.local/bin/skidbladnir-launch" "$stage/launcher-backup" 0755 || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir launcher target is invalid'
  }
  dev_server_snapshot_file "$unit_target" "$stage/unit-backup" 0644 || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir unit target is invalid'
  }

  [[ -e "$config/machine-handle" || -L "$config/machine-handle" ]] || credentials_installed=1
  skidbladnir_mint_secret "$generation/skidbladnir" "$config/machine-handle" machine \
    '^mh-[0-9a-f]{32}$' || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir machine handle is invalid'
  }
  [[ -e "$config/bearer" || -L "$config/bearer" ]] || credentials_installed=1
  skidbladnir_mint_secret "$generation/skidbladnir" "$config/bearer" bearer \
    '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir bearer is invalid'
  }
  if ((credentials_installed)); then
    render_result INSTALLED skidbladnir.credentials 'machine handle and bearer minted'
  fi

  unit_identity="$(skidbladnir_unit_identity "$platform")" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir unit identity is invalid'
  }
  skidbladnir_prepare_unit_generation "$platform" "$stage" "$units" "$unit_identity" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not preserve the desired Skidbladnir unit generation'
  }
  runtime_state="$home/.local/state/dev-server/active/skid.runtime.sha256"
  unit_state="$home/.local/state/dev-server/active/skid.unit.sha256"
  if active_runtime="$(skidbladnir_active_identity "$runtime_state")"; then :; else
    [[ "$?" == 1 ]] || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'Skidbladnir active runtime identity is invalid'
    }
    active_runtime=''
  fi
  if active_unit="$(skidbladnir_active_identity "$unit_state")"; then :; else
    [[ "$?" == 1 ]] || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'Skidbladnir active unit identity is invalid'
    }
    active_unit=''
  fi
  if [[ -n "$active_unit" ]]; then
    skidbladnir_unit_generation_owned "$units/$active_unit" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'recorded Skidbladnir unit generation is unavailable'
    }
  fi
  if [[ -n "$prior_current" ]]; then
    current_identity="$(skidbladnir_runtime_identity "$share/$prior_current")" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'current Skidbladnir runtime identity is invalid'
    }
  fi
  if [[ -n "$prior_previous" ]]; then
    previous_identity="$(skidbladnir_runtime_identity "$share/$prior_previous")" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'previous Skidbladnir runtime identity is invalid'
    }
    previous_version="$(jq -er '.version' "$share/$prior_previous/release.json")" || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'previous Skidbladnir generation manifest is invalid'
    }
  fi
  if [[ -n "$active_runtime" ]]; then
    if [[ "$active_runtime" == "$current_identity" ]]; then
      rollback_current="$prior_current"
      rollback_previous="$prior_previous"
      rollback_version="$prior_version"
    elif [[ -n "$prior_previous" && "$active_runtime" == "$previous_identity" ]]; then
      rollback_current="$prior_previous"
      rollback_previous=''
      rollback_version="$previous_version"
    else
      skidbladnir_discard_stage "$share" "$stage"
      die 'recorded active Skidbladnir runtime generation is unavailable'
    fi
  fi
  if ((was_active)) && [[ -n "$prior_current" ]]; then
    if skidbladnir_running_binary_matches "$platform" "$home" "$prior_current"; then
      verified_runtime=current
    elif [[ -n "$prior_previous" ]] &&
      skidbladnir_running_binary_matches "$platform" "$home" "$prior_previous"; then
      verified_runtime=previous
    fi
    if { [[ "$verified_runtime" == current ]] &&
      skidbladnir_authenticated_health "$home" "$prior_version" "$platform" "$prior_current"; } ||
      { [[ "$verified_runtime" == previous ]] &&
        skidbladnir_authenticated_health "$home" "$previous_version" "$platform" "$prior_previous"; }; then
      :
    else
      if [[ -n "$rollback_current" ]]; then
        if ! skidbladnir_restore_runtime "$platform" "$home" "$stage" \
          "$rollback_current" "$rollback_previous" "$rollback_version" \
          "$unit_target" "$was_enabled" "$active_unit"; then
          skidbladnir_discard_stage "$share" "$stage"
          die 'unhealthy interrupted Skidbladnir activation could not restore the verified prior runtime'
        fi
        skidbladnir_discard_stage "$share" "$stage"
        die 'unhealthy interrupted Skidbladnir activation; the verified prior runtime was restored'
      fi
      if [[ -z "$active_runtime" ]]; then
        if ! skidbladnir_restore_runtime "$platform" "$home" "$stage" '' '' '' \
          "$unit_target" "$was_enabled" ''; then
          skidbladnir_discard_stage "$share" "$stage"
          die 'unverified Skidbladnir activation could not be removed safely'
        fi
        skidbladnir_discard_stage "$share" "$stage"
        die 'unverified Skidbladnir first activation was stopped and unreferenced'
      fi
      skidbladnir_discard_stage "$share" "$stage"
      die 'running Skidbladnir generation is not healthy enough for safe activation'
    fi
    if [[ "$verified_runtime" == previous ]]; then
      rollback_current="$prior_previous"
      rollback_previous=''
      rollback_version="$previous_version"
    else
      rollback_current="$prior_current"
      rollback_previous="$prior_previous"
      rollback_version="$prior_version"
    fi
  fi

  skidbladnir_install_runtime_files "$platform" "$home" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not install Skidbladnir unit inputs'
  }
  if [[ "$prior_current" != "releases/$generation_name" ]]; then
    if [[ -n "$rollback_current" ]]; then
      skidbladnir_atomic_symlink "$share/previous" "$rollback_current" generation || {
        skidbladnir_discard_stage "$share" "$stage"
        die 'could not set the prior Skidbladnir generation'
      }
    else
      dev_server_remove_link "$share/previous" || {
        skidbladnir_discard_stage "$share" "$stage"
        die 'could not clear the prior Skidbladnir generation'
      }
    fi
    skidbladnir_atomic_symlink "$share/current" "releases/$generation_name" generation || {
      skidbladnir_discard_stage "$share" "$stage"
      die 'could not activate the Skidbladnir generation pointer'
    }
    pointer_changed=1
  fi

  if ((skidbladnir_unit_changed)) || [[ "$active_unit" != "$unit_identity" ]]; then
    needs_unit_reload=1
  fi
  if ((was_active == 0 || pointer_changed != 0 || needs_unit_reload != 0)) ||
    [[ "$active_runtime" != "$runtime_identity" || "$verified_runtime" == previous ]]; then
    needs_activation=1
  fi
  activation_failed=0
  if ! skidbladnir_activate_service "$platform" "$home" "$was_active" \
    "$needs_activation" "$needs_unit_reload"; then
    activation_failed=1
  elif ((needs_activation)); then
    if skidbladnir_wait_for_active "$platform"; then
      skidbladnir_authenticated_health "$home" "$version" "$platform" ||
        activation_failed=1
    else
      service_observation=$?
      if ((service_observation != 1)); then
        skidbladnir_discard_stage "$share" "$stage"
        die 'Skidbladnir activation state could not be observed; active identity was not advanced'
      fi
      activation_failed=1
    fi
  fi
  # Publish the human command only after activation succeeds. A failed upgrade
  # from a release without this command must not leave it pointing at old grammar.
  if ((activation_failed == 0)); then
    [[ -L "$home/.local/bin/skid" ]] || skidbladnir_command_installed=1
    skidbladnir_atomic_symlink "$home/.local/bin/skid" \
      '../share/skidbladnir/current/skidbladnir' binary || activation_failed=1
  fi
  if ((activation_failed)); then
    if ! skidbladnir_restore_runtime "$platform" "$home" "$stage" "$rollback_current" \
      "$rollback_previous" "$rollback_version" "$unit_target" \
      "$was_enabled" "$active_unit"; then
      skidbladnir_discard_stage "$share" "$stage"
      die 'Skidbladnir activation failed and the prior runtime could not be restored'
    fi
    skidbladnir_discard_stage "$share" "$stage"
    if [[ -n "$rollback_current" ]]; then
      die 'Skidbladnir activation failed; the verified prior runtime was restored'
    fi
    die 'Skidbladnir first activation failed; the candidate is inactive and unreferenced'
  fi
  ((pointer_changed == 0)) || render_result UPDATED skid.runtime "$generation_name"
  ((skidbladnir_unit_changed == 0)) ||
    render_result CHANGED skid.unit 'launcher and service definition installed'
  ((skidbladnir_command_installed == 0)) ||
    render_result INSTALLED skidbladnir.command "$home/.local/bin/skid and skidbladnir"
  ((skidbladnir_enablement_changed == 0)) ||
    render_result CHANGED skidbladnir.enablement 'enabled at login'
  [[ -z "$skidbladnir_activation_status" ]] ||
    render_result "$skidbladnir_activation_status" skid.runtime "$version"
  dev_server_record_active_sha skid.runtime "$runtime_identity" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not record the active Skidbladnir runtime identity'
  }
  dev_server_record_active_sha skid.unit "$unit_identity" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not record the active Skidbladnir unit identity'
  }

  skidbladnir_install_integrations "$platform" "$home" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not install Skidbladnir integrations'
  }
  skidbladnir_retain_generations "$home" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir release retention found an unowned generation'
  }
  skidbladnir_retain_unit_generations "$home" "$unit_identity" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'Skidbladnir unit retention found an unowned generation'
  }
  skidbladnir_retain_artifact "$artifact" || {
    skidbladnir_discard_stage "$share" "$stage"
    die 'could not remove an obsolete Skidbladnir artifact cache'
  }
  skidbladnir_discard_stage "$share" "$stage"
  dev_server_restore_signal_trap HUP "$saved_hup"
  dev_server_restore_signal_trap INT "$saved_int"
  dev_server_restore_signal_trap TERM "$saved_term"

  exec 9>&-
}
