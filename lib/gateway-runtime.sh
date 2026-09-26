#!/usr/bin/env bash
# shellcheck disable=SC2154,SC2015,SC2329 # product wrappers supply context; grouped install chains fail together.

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
: "${dev_server_install_status:=UP TO DATE}"
: "${dev_server_fleet_label_prefix:=dev.niels}"
gateway_unit_changed=0
gateway_activation_status=''
gateway_enablement_changed=0
gateway_command_installed=0

gateway_platform_key() {
  case "$1" in
  macos) printf 'darwin-arm64\n' ;;
  arch | devbox) printf 'linux-amd64\n' ;;
  *) die "unsupported gateway platform: $1" ;;
  esac
}

gateway_release_values() {
  local platform="$1"
  local artifact
  artifact="$(gateway_platform_key "$platform")"
  dev_server_strict_json_file "$gateway_release_pin_file" 4096 || return 1

  python3 - "$gateway_release_pin_file" "$artifact" "$gateway_repository" "$gateway_name" <<'PY'
import json
import re
import sys

with open(sys.argv[1], "r", encoding="utf-8") as stream:
    value = json.load(stream)
artifact = sys.argv[2]
if value == {"schemaVersion": 1, "status": "awaiting-original-skid-release"} or value == {
        "schemaVersion": 1, "status": "awaiting-herdr-mobile-release"}:
    raise SystemExit("separated gateway release is pending its app owner's published pin")
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
        "https://github.com/" + sys.argv[3] + "/releases/download/" +
        f"{version}/{sys.argv[4]}-{name}.tar.gz"
    )
    if (not isinstance(item, dict) or sorted(item) != ["sha256", "url"] or
            item.get("url") != expected or not isinstance(item.get("sha256"), str) or
            not re.fullmatch(r"[0-9a-f]{64}", item["sha256"])):
        raise SystemExit(1)
print("\t".join((version, source, artifacts[artifact]["url"],
                  artifacts[artifact]["sha256"], artifact)))
PY
}

gateway_pin_pending() {
  dev_server_strict_json_file "$gateway_release_pin_file" 4096 || return 1
  python3 - "$gateway_release_pin_file" "$gateway_name" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
raise SystemExit(0 if value == {"schemaVersion": 1,
    "status": "awaiting-" + ("original-skid" if sys.argv[2] == "skidbladnir"
                            else "herdr-mobile") + "-release"} else 1)
PY
}

gateway_release_manifest_matches() {
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

gateway_validate_declared_inputs() {
  local platform="$1"
  local path
  local -a regular_files=("${gateway_name}-launch")

  case "$platform" in
  macos) regular_files+=("dev.niels.${gateway_name}.plist") ;;
  arch | devbox) regular_files+=("${gateway_name}.service") ;;
  *) die "unsupported gateway platform: $platform" ;;
  esac

  require_cmd python3
  gateway_release_values "$platform" >/dev/null ||
    die "$gateway_name release pin is invalid"
  for path in "${regular_files[@]}"; do
    path="$(dev_server_assets_dir)/${gateway_name}/$path"
    [[ -f "$path" && ! -L "$path" ]] ||
      die "invalid gateway declared file: $path"
  done
  path="$(dev_server_assets_dir)/${gateway_name}/host-config.json"
  dev_server_strict_json_file "$path" 65536 ||
    die "invalid gateway declared JSON: $path"
  gateway_unit_identity "$platform" >/dev/null ||
    die 'gateway unit inputs are invalid'
}

gateway_validate_local_state() {
  local home="$1"
  local config="$home/.config/${gateway_name}"

  gateway_validate_protected_paths "$home"
  gateway_validate_present_credentials "$config" ||
    die 'existing gateway credentials are invalid'
  gateway_validate_active_journals "$home" ||
    die 'existing gateway active identity is invalid'
}

gateway_namespace_marker_valid() {
  local path="$1" value framed
  [[ -f "$path" && ! -L "$path" && "$(file_mode "$path" 2>/dev/null)" == 600 ]] || return 1
  value="$(cat "$path")" || return 1
  framed="$(cat "$path" && printf .)" || return 1
  [[ "$framed" == "$value"$'\n.' && "$value" == "$gateway_name separated-v1" ]]
}

gateway_validate_namespace() {
  local home="$1" platform="$2" config="$1/.config/$gateway_name"
  local share="$1/.local/share/$gateway_name"
  local marker="$config/deployment-identity" path unit
  if [[ -e "$marker" || -L "$marker" ]]; then
    gateway_namespace_marker_valid "$marker" || die "invalid $gateway_name deployment identity"
    return 0
  fi
  unit="$(gateway_unit_target "$platform" "$home")" || return 1
  for path in "$config/bearer" "$config/machine-handle" "$config/client.json" \
    "$home/.local/bin/${gateway_name}" "$home/.local/bin/${gateway_name}-launch" "$unit" \
    "$share/current" "$share/previous" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.pair" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.runtime.sha256" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.unit.sha256"; do
    if [[ -e "$path" || -L "$path" ]]; then
      die "$gateway_name namespace has credentials or runtime state without separated deployment identity"
    fi
  done
  if [[ "$gateway_name" == skidbladnir ]]; then
    for path in "$home/.local/bin/skid" "$home/.local/bin/skidbladnir-provider-runtime-control" \
      "$share/claude-agent-identity"; do
      [[ ! -e "$path" && ! -L "$path" ]] ||
        die 'skid namespace has command or provider links without separated deployment identity'
    done
  fi
  for path in "$share/releases" "$share/artifacts" "$share/units"; do
    if [[ -d "$path" && -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      die "$gateway_name has generations without separated deployment identity"
    fi
  done
}

gateway_secret_valid() (
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

gateway_validate_present_credentials() {
  local config="$1"
  local path

  if [[ -e "$config/machine-handle" || -L "$config/machine-handle" ]]; then
    gateway_secret_valid "$config/machine-handle" '^mh-[0-9a-f]{32}$' ||
      return 1
  fi
  if [[ -e "$config/bearer" || -L "$config/bearer" ]]; then
    gateway_secret_valid "$config/bearer" \
      '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || return 1
  fi
}

gateway_prepare_directories() {
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
  dev_server_reconcile_directory "$home/.local/share/${gateway_name}" 0700
  dev_server_reconcile_directory "$home/.local/share/${gateway_name}/artifacts" 0700
  dev_server_reconcile_directory "$home/.local/share/${gateway_name}/releases" 0700
  dev_server_reconcile_directory "$home/.local/share/${gateway_name}/units" 0700
  dev_server_reconcile_directory "$home/.local/state" 0755
  dev_server_reconcile_directory "$home/.local/state/dev-server" 0700
  dev_server_reconcile_directory "$home/.local/state/dev-server/active" 0700
  dev_server_reconcile_directory "$home/.local/state/${gateway_name}" 0700
  dev_server_reconcile_directory "$home/.config" 0755
  dev_server_reconcile_directory "$home/.config/${gateway_name}" 0700
  if [[ "$2" == macos ]]; then
    dev_server_reconcile_directory "$home/Library" 0755
  else
    dev_server_reconcile_directory "$home/.config/systemd" 0755
  fi
  dev_server_reconcile_directory "$service_parent" 0755
}

gateway_validate_link() {
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
  binary:../share/*/current/*) ;;
  helper:../share/skidbladnir/current/providers/native-control) ;;
  plugin:current/providers/claude-agent-identity) ;;
  *) return 2 ;;
  esac
  if [[ "$kind" == generation ]]; then
    [[ "$value" =~ ^releases/v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})-[0-9a-f]{64}$ ]] || return 2
  fi
  if [[ "$kind" == binary && "$value" != "../share/$gateway_name/current/$gateway_name" ]]; then return 2; fi
  printf '%s\n' "$value"
}

gateway_validate_protected_paths() {
  local home="$1"
  local share="$home/.local/share/${gateway_name}"
  local config="$home/.config/${gateway_name}"
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
      [[ -d "$path" && ! -L "$path" ]] || die "protected gateway directory is invalid: $path"
    fi
  done
  for link in "$share/current" "$share/previous"; do
    if [[ -e "$link" || -L "$link" ]]; then
      gateway_validate_link "$link" generation >/dev/null ||
        die "protected gateway link is invalid: $link"
    fi
  done
  link="$home/.local/bin/${gateway_name}"
  if [[ -e "$link" || -L "$link" ]]; then
    gateway_validate_link "$link" binary >/dev/null ||
      die "protected gateway link is invalid: $link"
  fi
  if [[ "$gateway_name" == skidbladnir ]]; then
    link="$home/.local/bin/skid"
    if [[ -e "$link" || -L "$link" ]]; then
      gateway_validate_link "$link" binary >/dev/null ||
        die "protected skid command link is invalid: $link"
    fi
    link="$home/.local/bin/skidbladnir-provider-runtime-control"
    if [[ -e "$link" || -L "$link" ]]; then
      gateway_validate_link "$link" helper >/dev/null ||
        die "protected skid helper link is invalid: $link"
    fi
    link="$share/claude-agent-identity"
    if [[ -e "$link" || -L "$link" ]]; then
      gateway_validate_link "$link" plugin >/dev/null ||
        die "protected skid plugin link is invalid: $link"
    fi
  fi
  for path in \
    "$config/bearer" \
    "$config/machine-handle" \
    "$config/deployment-identity"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -f "$path" && ! -L "$path" ]] || die "protected gateway credential is invalid: $path"
    fi
  done
}

gateway_validate_active_journals() {
  local home="$1"
  local path status

  for path in \
    "$home/.local/state/dev-server/active/${gateway_receipt}.runtime.sha256" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.unit.sha256"; do
    if gateway_active_identity "$path" >/dev/null; then
      continue
    else
      status=$?
    fi
    ((status == 1)) || return 1
  done
  path="$home/.local/state/dev-server/active/${gateway_receipt}.pair"
  if gateway_active_pair "$path" >/dev/null; then
    :
  else
    status=$?
    ((status == 1)) || return 1
  fi
}

gateway_discard_stage() {
  dev_server_remove_stage "$1" "$2" ||
    die 'could not remove the gateway staging directory'
}

# after gateway_restore_runtime failed with STATUS: 4 keeps the stage (the
# prior launcher and unit are still only there) and reports; anything else
# discards it and returns to the caller's own text.
gateway_settle_failed_restore() {
  local share="$1"
  local stage="$2"
  local status="$3"
  local retained

  if ((status == 4)); then
    retained="$(dev_server_retain_stage "$share" "$stage")" ||
      die 'gateway activation failed, the candidate could not be stopped, and its stage could not be kept'
    die "gateway activation failed and the candidate could not be stopped; its inputs remain in place and the prior launcher and unit are kept in $retained"
  fi
  gateway_discard_stage "$share" "$stage"
}

gateway_archive_members_exact() {
  local archive="$1"
  local members types

  members="$(tar -tzf "$archive" 2>/dev/null | LC_ALL=C sort)" || return 1
  [[ "$members" == "$(printf 'characters.json\nrelease.json\n%s\n' "$gateway_name" | LC_ALL=C sort)" ]] || return 1
  types="$(tar -tvzf "$archive" 2>/dev/null | LC_ALL=C awk '{print substr($1,1,1)}' | LC_ALL=C sort)" || return 1
  [[ "$types" == $'-\n-\n-' ]]
}

gateway_prepare_artifact() {
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
    identity="$(gateway_active_identity "$artifact/identity.sha256")" || return 6
    [[ "$(gateway_payload_hashes "$artifact" | dev_server_sha256_stream)" == "$identity" ]] || return 6
    [[ "$(file_mode "$artifact/${gateway_name}")" == 755 &&
    "$(file_mode "$artifact/characters.json")" == 644 &&
    "$(file_mode "$artifact/release.json")" == 644 ]] || return 6
    gateway_release_manifest_matches "$artifact/release.json" \
      "$manifest_platform" "$source_sha" "$version" || return 4
    return 0
  fi
  dev_server_download "$url" "$archive" || return 1
  [[ "$(dev_server_sha256 "$archive")" == "$archive_sha" ]] || return 2
  gateway_archive_members_exact "$archive" || return 3
  mkdir -m 0700 "$payload" || return 1
  tar --no-same-owner --no-same-permissions -xzf "$archive" -C "$payload" \
    "$gateway_name" characters.json release.json || return 3
  [[ -f "$payload/${gateway_name}" && ! -L "$payload/${gateway_name}" ]] || return 3
  [[ -f "$payload/characters.json" && ! -L "$payload/characters.json" ]] || return 3
  [[ -f "$payload/release.json" && ! -L "$payload/release.json" ]] || return 3
  chmod 0755 "$payload/${gateway_name}" || return 1
  chmod 0644 "$payload/characters.json" "$payload/release.json" || return 1
  gateway_release_manifest_matches "$payload/release.json" \
    "$manifest_platform" "$source_sha" "$version" || return 4
  framed="$("$payload/${gateway_name}" version && printf .)" || return 5
  identity="${framed%$'\n.'}"
  [[ "$framed" == "$identity"$'\n.' && "$identity" == "$version $source_sha" ]] || return 5
  gateway_payload_hashes "$payload" | dev_server_sha256_stream >"$payload/identity.sha256" || return 1
  chmod 0600 "$payload/identity.sha256" || return 1
  mv "$payload" "$artifact"
}

gateway_generation_exact() {
  local desired="$1"
  local installed="$2"
  local host_config="$3"
  local staged_providers="${4:-}"

  gateway_generation_owned "$installed" || return 1
  cmp -s "$desired/${gateway_name}" "$installed/${gateway_name}" &&
    cmp -s "$desired/characters.json" "$installed/characters.json" &&
    cmp -s "$desired/release.json" "$installed/release.json" &&
    cmp -s "$host_config" "$installed/host-config.json" || return 1
  if [[ "$gateway_name" == skidbladnir ]]; then
    local name
    for name in native-control provider-command shell-init \
      claude-agent-identity/.claude-plugin/plugin.json \
      claude-agent-identity/hooks/hooks.json \
      claude-agent-identity/bin/agent-hook; do
      cmp -s "$staged_providers/$name" "$installed/providers/$name" || return 1
    done
  fi
}

gateway_payload_hashes() {
  local payload="$1"
  local name digest

  for name in "$gateway_name" characters.json release.json; do
    digest="$(dev_server_sha256 "$payload/$name")" || return 1
    printf '%s\0%s\n' "$name" "$digest"
  done
}

gateway_runtime_identity() {
  local generation="$1"
  local host_config="${2:-$generation/host-config.json}"
  local providers="${3:-$generation/providers}"
  local digest name

  digest="$(dev_server_sha256 "$host_config")" || return 1
  {
    gateway_payload_hashes "$generation" || return 1
    printf 'host-config.json\0%s\n' "$digest"
    if [[ "$gateway_name" == skidbladnir ]]; then
      for name in native-control provider-command shell-init \
        claude-agent-identity/.claude-plugin/plugin.json \
        claude-agent-identity/hooks/hooks.json \
        claude-agent-identity/bin/agent-hook; do
        digest="$(dev_server_sha256 "$providers/$name")" || return 1
        printf 'providers/%s\0%s\n' "$name" "$digest"
      done
    fi
  } | dev_server_sha256_stream
}

gateway_unit_source() {
  case "$1" in
  macos) printf '%s/%s/dev.niels.%s.plist\n' "$(dev_server_assets_dir)" "$gateway_name" "$gateway_name" ;;
  arch | devbox) printf '%s/%s/%s.service\n' "$(dev_server_assets_dir)" "$gateway_name" "$gateway_name" ;;
  *) return 1 ;;
  esac
}

gateway_unit_target() {
  case "$1" in
  macos) printf '%s/Library/LaunchAgents/%s.%s.plist\n' "$2" "$dev_server_fleet_label_prefix" "$gateway_name" ;;
  arch | devbox) printf '%s/.config/systemd/user/%s.service\n' "$2" "$gateway_name" ;;
  *) return 1 ;;
  esac
}

gateway_unit_identity() {
  local platform="$1"
  local launcher unit
  launcher="$(dev_server_assets_dir)/${gateway_name}/${gateway_name}-launch"
  unit="$(gateway_unit_source "$platform")" || return 1
  gateway_unit_files_identity "$launcher" "$unit"
}

gateway_unit_files_identity() {
  local launcher="$1"
  local unit="$2"

  [[ -f "$launcher" && ! -L "$launcher" &&
    -f "$unit" && ! -L "$unit" ]] || return 1
  printf 'launcher\0%s\nunit\0%s\n' \
    "$(dev_server_sha256 "$launcher")" "$(dev_server_sha256 "$unit")" |
    dev_server_sha256_stream
}

gateway_unit_generation_owned() {
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
  [[ "$(gateway_unit_files_identity "$path/launcher" "$path/unit")" == "$name" ]]
}

gateway_prepare_unit_generation() {
  local platform="$1"
  local stage="$2"
  local units="$3"
  local identity="$4"
  local candidate="$stage/unit-generation"
  local installed="$units/$identity"
  local launcher unit

  launcher="$(dev_server_assets_dir)/${gateway_name}/${gateway_name}-launch"
  unit="$(gateway_unit_source "$platform")" || return 1
  if [[ -e "$installed" || -L "$installed" ]]; then
    gateway_unit_generation_owned "$installed" || return 1
    cmp -s "$launcher" "$installed/launcher" && cmp -s "$unit" "$installed/unit"
    return
  fi
  mkdir -m 0700 "$candidate" || return 1
  install -m 0755 "$launcher" "$candidate/launcher" || return 1
  install -m 0644 "$unit" "$candidate/unit" || return 1
  [[ "$(gateway_unit_files_identity "$candidate/launcher" "$candidate/unit")" == "$identity" ]] ||
    return 1
  mv "$candidate" "$installed" || return 1
  gateway_unit_generation_owned "$installed"
}

gateway_promote_secret() {
  python3 - "$1" "$2" <<'PY'
import os
import sys

# A hard-link promotion is same-filesystem and fails rather than replacing a
# credential created concurrently. Unlinking the staging name leaves one file.
os.link(sys.argv[1], sys.argv[2], follow_symlinks=False)
os.unlink(sys.argv[1])
PY
}

gateway_atomic_symlink() {
  local target="$1"
  local relative="$2"
  local kind="$3"

  case "$kind:$relative" in
  generation:releases/v*-????????????????????????????????????????????????????????????????) ;;
  binary:../share/*/current/*) ;;
  helper:../share/skidbladnir/current/providers/native-control) ;;
  plugin:current/providers/claude-agent-identity) ;;
  *) return 1 ;;
  esac
  [[ "$kind" != binary || "$relative" == "../share/$gateway_name/current/$gateway_name" ]] || return 1
  dev_server_atomic_symlink "$target" "$relative"
}

gateway_mint_secret() (
  local binary="$1"
  local target="$2"
  local kind="$3"
  local pattern="$4"
  local parent name staging='' temporary

  parent="$(dirname "$target")"
  name="$(basename "$target")"
  gateway_secret_stage_cleanup() {
    if [[ -n "$staging" && "$(dirname "$staging")" == "$parent" &&
    "$(basename "$staging")" =~ ^\.${name}\.dev-server\.[A-Za-z0-9]{6}$ &&
    -d "$staging" && ! -L "$staging" ]]; then
      rm -R -- "$staging"
    fi
  }
  trap gateway_secret_stage_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if [[ -e "$target" || -L "$target" ]]; then
    gateway_secret_valid "$target" "$pattern"
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
  gateway_secret_valid "$temporary" "$pattern" || {
    return 1
  }
  if ! gateway_promote_secret "$temporary" "$target"; then
    gateway_secret_valid "$target" "$pattern"
    return
  fi
  gateway_secret_valid "$target" "$pattern"
)

gateway_active_identity() {
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

# One atomic authority binds the verified runtime to the exact unit generation.
# The historical .runtime/.unit stems remain operator-visible receipts only.
gateway_active_pair() {
  local path="$1" value framed
  if [[ ! -e "$path" && ! -L "$path" ]]; then return 1; fi
  [[ -f "$path" && ! -L "$path" && "$(file_mode "$path" 2>/dev/null)" == 600 ]] || return 2
  value="$(cat "$path")" || return 2
  framed="$(cat "$path" && printf .)" || return 2
  [[ "$framed" == "$value"$'\n.' &&
    "$value" =~ ^[0-9a-f]{64}\ [0-9a-f]{64}$ ]] || return 2
  printf '%s\n' "$value"
}

gateway_record_pair() {
  local stage="$1" home="$2" runtime="$3" unit="$4"
  [[ "$runtime" =~ ^[0-9a-f]{64}$ && "$unit" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s %s\n' "$runtime" "$unit" >"$stage/active.pair" || return 1
  atomic_install_file "$stage/active.pair" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.pair" 0600
}

gateway_service_state() {
  case "$1" in
  arch | devbox) dev_server_service_state "$1" "${gateway_name}.service" ;;
  macos) dev_server_service_state "$1" "$dev_server_fleet_label_prefix.${gateway_name}" ;;
  *) return 2 ;;
  esac
}

gateway_service_active() {
  local state

  state="$(gateway_service_state "$1")" || return 2
  [[ "$state" == active ]]
}

gateway_wait_for_active() {
  local platform="$1"
  local attempt observation

  for attempt in 1 2 3 4 5; do
    if gateway_service_active "$platform"; then
      return 0
    else
      observation=$?
    fi
    ((observation == 1)) || return 2
    ((attempt == 5)) || sleep 1
  done
  return 1
}

gateway_service_enabled() {
  case "$1" in
  arch | devbox) dev_server_service_enabled "$1" "${gateway_name}.service" ;;
  macos) dev_server_service_enabled "$1" "$dev_server_fleet_label_prefix.${gateway_name}" ;;
  *) return 1 ;;
  esac
}

gateway_activate_service() {
  local platform="$1"
  local home="$2"
  local was_active="$3"
  local needs_activation="$4"
  local unit_changed="$5"
  local target domain label enabled_status state

  gateway_activation_status=''
  gateway_enablement_changed=0
  case "$platform" in
  arch | devbox)
    if ((unit_changed)); then
      systemctl --user daemon-reload || return 1
    fi
    if gateway_service_enabled "$platform"; then
      enabled_status=0
    else
      enabled_status=$?
    fi
    if ((enabled_status != 0)); then
      ((enabled_status == 1)) || return 1
      systemctl --user enable "${gateway_name}.service" || return 1
      gateway_enablement_changed=1
    fi
    if ((was_active)); then
      if ((needs_activation)); then
        systemctl --user restart "${gateway_name}.service" || return 1
        gateway_activation_status=RESTARTED
      fi
    else
      systemctl --user start "${gateway_name}.service" || return 1
      gateway_activation_status=STARTED
    fi
    ;;
  macos)
    target="$(gateway_unit_target "$platform" "$home")"
    domain="gui/$(id -u)"
    label="$dev_server_fleet_label_prefix.${gateway_name}"
    if gateway_service_enabled "$platform"; then
      enabled_status=0
    else
      enabled_status=$?
    fi
    if ((enabled_status != 0)); then
      ((enabled_status == 1)) || return 1
      launchctl enable "$domain/$label" || return 1
      gateway_enablement_changed=1
    fi
    if ((was_active && !needs_activation)); then
      return 0
    fi
    # launchd retains the loaded definition even while its process is stopped.
    state="$(gateway_service_state "$platform")" || return 1
    if [[ "$state" != absent ]] && ((unit_changed)); then
      gateway_stop_service "$platform" || return 1
      state=absent
    fi
    if [[ "$state" == absent ]]; then
      launchctl bootstrap "$domain" "$target" || return 1
    else
      launchctl kickstart -k "$domain/$label" || return 1
    fi
    if ((was_active)); then
      gateway_activation_status=RESTARTED
    else
      gateway_activation_status=STARTED
    fi
    ;;
  *) return 1 ;;
  esac
}

# 0 once the supervisor has torn the service down or when it was already absent.
gateway_stop_service() {
  case "$1" in
  macos) dev_server_stop_service macos "$dev_server_fleet_label_prefix.${gateway_name}" ;;
  arch | devbox) dev_server_stop_service "$1" "${gateway_name}.service" ;;
  *) return 1 ;;
  esac
}

gateway_running_binary_matches() {
  local platform="$1"
  local home="$2"
  local runtime_ref="${3:-current}"
  local expected
  local pid executable

  case "$runtime_ref" in
  current | releases/v*-????????????????????????????????????????????????????????????????) ;;
  *) return 1 ;;
  esac
  expected="$home/.local/share/${gateway_name}/$runtime_ref/${gateway_name}"
  expected="$(cd "$(dirname "$expected")" && pwd -P)/$(basename "$expected")" || return 1

  case "$platform" in
  arch | devbox)
    pid="$(dev_server_service_main_pid "$platform" "${gateway_name}.service")" || return 1
    executable="$(readlink "/proc/$pid/exe" 2>/dev/null)" || return 1
    [[ "$executable" == "$expected" && -f "$executable" && ! -L "$executable" ]] || return 1
    ;;
  macos)
    pid="$(dev_server_service_main_pid "$platform" "$dev_server_fleet_label_prefix.${gateway_name}")" || return 1
    /usr/sbin/lsof -a -p "$pid" -d txt -Fn 2>/dev/null |
      grep -Fqx "n$expected" || return 1
    ;;
  *) return 1 ;;
  esac
}

gateway_authenticated_health() (
  set +x
  local home="$1"
  local expected_version="$2"
  local platform="${3:-}"
  local runtime_ref="${4:-current}"
  local config="$home/.config/${gateway_name}"
  local response bytes observed_version attempt

  gateway_secret_valid "$config/machine-handle" '^mh-[0-9a-f]{32}$' || return 1
  gateway_secret_valid "$config/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || return 1
  observed_version="$(jq -er '.version' "$home/.local/share/${gateway_name}/$runtime_ref/release.json")" || return 1
  [[ "$observed_version" == "$expected_version" ]] || return 1
  for attempt in 1 2 3 4 5; do
    response="$({
      printf 'silent\nshow-error\nfail\nconnect-timeout = 1\nmax-time = 2\nmax-filesize = 65536\n'
      printf 'header = "Authorization: Bearer %s"\n' "$(cat "$config/bearer")"
      printf 'header = "%s: %s"\n' "$gateway_machine_header" "$(cat "$config/machine-handle")"
      printf 'url = "http://127.0.0.1:%s/v1/pressure"\n' "$gateway_port"
    } | curl -q --noproxy '*' --config - 2>/dev/null || true)"
    bytes="$(LC_ALL=C printf '%s' "$response" | wc -c | tr -d '[:space:]')"
    if [[ "$bytes" =~ ^[1-9][0-9]*$ && "$bytes" -le 65536 ]] &&
      printf '%s' "$response" | jq -e '
        type == "object" and
        (.current | type == "object") and
        (.history | type == "array") and
        (.unsupported | type == "array")
      ' >/dev/null 2>&1 &&
      { [[ -z "$platform" ]] || gateway_running_binary_matches "$platform" "$home" "$runtime_ref"; }; then
      return 0
    fi
    ((attempt == 5)) || sleep 1
  done
  return 1
)

# undoes a failed activation in this order: confirmed stop of the candidate,
# then launcher, unit, pointers and command links go back, then the prior
# runtime restarts and verifies. 0 restored; 4 the candidate could not be
# stopped, so nothing moved and the stage still holds the prior's backups;
# 1 the restore itself failed.
gateway_restore_runtime() {
  local platform="$1"
  local home="$2"
  local stage="$3"
  local prior_current="$4"
  local prior_previous="$5"
  local prior_version="$6"
  local unit_target="$7"
  local was_enabled="$8"
  local active_unit="$9"
  local share="$home/.local/share/${gateway_name}"
  local unit_generation

  gateway_stop_service "$platform" || return 4
  if [[ -z "$prior_current" && "$platform" != macos && "$was_enabled" == 0 ]]; then
    # systemd needs the unit file to remove its enablement links.
    systemctl --user disable "${gateway_name}.service" >/dev/null 2>&1 || return 1
  fi

  if [[ -n "$active_unit" ]]; then
    unit_generation="$share/units/$active_unit"
    gateway_unit_generation_owned "$unit_generation" || return 1
    atomic_install_file "$unit_generation/launcher" \
      "$home/.local/bin/${gateway_name}-launch" 0755 || return 1
    atomic_install_file "$unit_generation/unit" "$unit_target" 0644 || return 1
  elif [[ -z "$prior_current" ]]; then
    for unit_generation in "$home/.local/bin/${gateway_name}-launch" "$unit_target"; do
      if [[ -e "$unit_generation" || -L "$unit_generation" ]]; then
        [[ -f "$unit_generation" && ! -L "$unit_generation" ]] || return 1
        rm -f -- "$unit_generation" || return 1
      fi
    done
  else
    dev_server_restore_file "$home/.local/bin/${gateway_name}-launch" \
      "$stage/launcher-backup" 0755 || return 1
    dev_server_restore_file "$unit_target" "$stage/unit-backup" 0644 || return 1
  fi
  if [[ -n "$prior_current" ]]; then
    gateway_atomic_symlink "$share/current" "$prior_current" generation || return 1
  else
    dev_server_remove_link "$share/current" || return 1
  fi
  if [[ -n "$prior_previous" ]]; then
    gateway_atomic_symlink "$share/previous" "$prior_previous" generation || return 1
  else
    dev_server_remove_link "$share/previous" || return 1
  fi
  if [[ -z "$prior_current" ]]; then
    dev_server_remove_link "$home/.local/bin/${gateway_name}" || return 1
    if [[ "$gateway_name" == skidbladnir ]]; then
      dev_server_remove_link "$home/.local/bin/skid" || return 1
      dev_server_remove_link "$home/.local/bin/skidbladnir-provider-runtime-control" || return 1
      dev_server_remove_link "$share/claude-agent-identity" || return 1
    fi
  fi

  if [[ -z "$prior_current" ]]; then
    if [[ "$platform" != macos ]]; then
      systemctl --user daemon-reload >/dev/null 2>&1 || true
    fi
  else
    if [[ "$platform" == macos ]]; then
      launchctl bootstrap "gui/$(id -u)" "$unit_target" || return 1
    else
      systemctl --user daemon-reload || return 1
      systemctl --user restart "${gateway_name}.service" || return 1
    fi
    gateway_authenticated_health "$home" "$prior_version" "$platform" || return 1
  fi

  # A disabled service can still be running. Restore that durable preference
  # only after the prior runtime has been bootstrapped and verified.
  if [[ "$was_enabled" == 0 ]]; then
    if [[ "$platform" == macos ]]; then
      launchctl disable "gui/$(id -u)/$dev_server_fleet_label_prefix.${gateway_name}" >/dev/null 2>&1 || return 1
    elif [[ -n "$prior_current" ]]; then
      systemctl --user disable "${gateway_name}.service" >/dev/null 2>&1 || return 1
    fi
  fi
}

gateway_install_runtime_files() {
  local platform="$1"
  local home="$2"
  local unit_source unit_target launcher_source

  unit_source="$(gateway_unit_source "$platform")" || return 1
  unit_target="$(gateway_unit_target "$platform" "$home")" || return 1
  launcher_source="$(dev_server_assets_dir)/${gateway_name}/${gateway_name}-launch"
  gateway_unit_changed=0
  gateway_command_installed=0

  atomic_install_file "$launcher_source" "$home/.local/bin/${gateway_name}-launch" 0755 || return 1
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || gateway_unit_changed=1
  atomic_install_file "$unit_source" "$unit_target" 0644 || return 1
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || gateway_unit_changed=1
  [[ -L "$home/.local/bin/${gateway_name}" ]] || gateway_command_installed=1
  gateway_atomic_symlink "$home/.local/bin/${gateway_name}" \
    "../share/$gateway_name/current/$gateway_name" binary || return 1
  if [[ "$gateway_name" == skidbladnir ]]; then
    [[ -L "$home/.local/bin/skid" ]] || gateway_command_installed=1
    gateway_atomic_symlink "$home/.local/bin/skid" \
      '../share/skidbladnir/current/skidbladnir' binary || return 1
    gateway_atomic_symlink "$home/.local/bin/skidbladnir-provider-runtime-control" \
      '../share/skidbladnir/current/providers/native-control' helper || return 1
    gateway_atomic_symlink "$home/.local/share/skidbladnir/claude-agent-identity" \
      'current/providers/claude-agent-identity' plugin || return 1
  fi
}

gateway_generation_owned() {
  local path="$1"
  local name entries
  name="$(basename "$path")"
  [[ "$name" =~ ^v(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})\.(0|[1-9][0-9]{0,3})-[0-9a-f]{64}$ ]] || return 1
  [[ -d "$path" && ! -L "$path" &&
    "$(_dev_server_observed_mode user "$path" 2>/dev/null)" == 700 ]] || return 1
  entries="$(find "$path" -mindepth 1 -maxdepth 1 -print | sed "s#^$path/##" | LC_ALL=C sort)" || return 1
  if [[ "$gateway_name" == skidbladnir ]]; then
    [[ "$entries" == "$(printf 'characters.json\nhost-config.json\nproviders\nrelease.json\n%s\n' "$gateway_name" | LC_ALL=C sort)" ]] || return 1
    [[ -d "$path/providers" && ! -L "$path/providers" &&
      "$(find "$path/providers" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)" == $'claude-agent-identity\nnative-control\nprovider-command\nshell-init' ]] || return 1
    local provider_file mode
    for provider_file in native-control provider-command shell-init \
      claude-agent-identity/.claude-plugin/plugin.json \
      claude-agent-identity/hooks/hooks.json \
      claude-agent-identity/bin/agent-hook; do
      mode=644
      case "$provider_file" in native-control | provider-command | */bin/agent-hook) mode=755 ;; esac
      [[ -f "$path/providers/$provider_file" && ! -L "$path/providers/$provider_file" &&
        "$(file_mode "$path/providers/$provider_file" 2>/dev/null)" == "$mode" ]] || return 1
    done
    for provider_file in claude-agent-identity \
      claude-agent-identity/.claude-plugin \
      claude-agent-identity/hooks \
      claude-agent-identity/bin; do
      [[ -d "$path/providers/$provider_file" && ! -L "$path/providers/$provider_file" &&
        "$(stat -c '%a' "$path/providers/$provider_file" 2>/dev/null ||
          stat -f '%Lp' "$path/providers/$provider_file" 2>/dev/null)" == 755 ]] || return 1
    done
    [[ "$(find "$path/providers/claude-agent-identity" -mindepth 1 -maxdepth 3 -print | sed "s#^$path/providers/claude-agent-identity/##" | LC_ALL=C sort)" == \
      $'.claude-plugin\n.claude-plugin/plugin.json\nbin\nbin/agent-hook\nhooks\nhooks/hooks.json' ]] || return 1
  else
    [[ "$entries" == "$(printf 'characters.json\nhost-config.json\nrelease.json\n%s\n' "$gateway_name" | LC_ALL=C sort)" ]] || return 1
  fi
  [[ -f "$path/${gateway_name}" && ! -L "$path/${gateway_name}" &&
    -f "$path/characters.json" && ! -L "$path/characters.json" &&
    -f "$path/release.json" && ! -L "$path/release.json" &&
    -f "$path/host-config.json" && ! -L "$path/host-config.json" ]] || return 1
  [[ "$(file_mode "$path/${gateway_name}" 2>/dev/null)" == 755 &&
    "$(file_mode "$path/characters.json" 2>/dev/null)" == 644 &&
    "$(file_mode "$path/release.json" 2>/dev/null)" == 644 &&
    "$(file_mode "$path/host-config.json" 2>/dev/null)" == 600 ]] || return 1
  "$gateway_generation_validator" "$path/host-config.json" || return 1
  [[ "$(gateway_runtime_identity "$path")" == "${name##*-}" ]]
}

gateway_validate_installed_generations() {
  local home="$1"
  local share="$home/.local/share/${gateway_name}"
  local releases="$share/releases"
  local path link relative
  while IFS= read -r -d '' path; do
    gateway_generation_owned "$path" || return 1
  done < <(find "$releases" -mindepth 1 -maxdepth 1 -print0)
  for link in "$share/current" "$share/previous"; do
    if [[ -L "$link" ]]; then
      relative="$(readlink "$link")" || return 1
      gateway_generation_owned "$share/$relative" || return 1
    fi
  done
}

gateway_validate_installed_unit_generations() {
  local home="$1"
  local units="$home/.local/share/${gateway_name}/units"
  local path

  while IFS= read -r -d '' path; do
    gateway_unit_generation_owned "$path" || return 1
  done < <(find "$units" -mindepth 1 -maxdepth 1 -print0)
}

gateway_retain_generations() {
  local home="$1"
  local releases="$home/.local/share/${gateway_name}/releases"
  local current previous path relative

  current="$(readlink "$home/.local/share/${gateway_name}/current")" || return 1
  previous=''
  if [[ -L "$home/.local/share/${gateway_name}/previous" ]]; then
    previous="$(readlink "$home/.local/share/${gateway_name}/previous")" || return 1
  fi
  while IFS= read -r -d '' path; do
    relative="releases/$(basename "$path")"
    if [[ "$relative" == "$current" || "$relative" == "$previous" ]]; then
      continue
    fi
    gateway_generation_owned "$path" || return 1
    rm -R -- "$path" || return 1
  done < <(find "$releases" -mindepth 1 -maxdepth 1 -print0)
}

gateway_retain_unit_generations() {
  local home="$1"
  local desired="$2"
  local units="$home/.local/share/${gateway_name}/units"
  local path

  [[ "$desired" =~ ^[0-9a-f]{64}$ ]] || return 1
  while IFS= read -r -d '' path; do
    [[ "$(basename "$path")" == "$desired" ]] && continue
    gateway_unit_generation_owned "$path" || return 1
    rm -R -- "$path" || return 1
  done < <(find "$units" -mindepth 1 -maxdepth 1 -print0)
}

gateway_retain_artifact() {
  local desired="$1"
  local path name entries owned

  # Rollback generations already contain their complete payload. Keep only the
  # desired cache; leave unrelated files and directories alone.
  for path in "$(dirname "$desired")"/*; do
    [[ "$path" != "$desired" && -d "$path" && ! -L "$path" ]] || continue
    name="${path##*/}"
    [[ "$name" =~ ^[0-9a-f]{64}$ ]] || continue
    entries="$(find "$path" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)" || return 1
    [[ "$entries" == "$(printf 'characters.json\nidentity.sha256\nrelease.json\n%s\n' "$gateway_name" | LC_ALL=C sort)" ]] || continue
    owned=1
    for name in "$gateway_name" characters.json release.json identity.sha256; do
      [[ -f "$path/$name" && ! -L "$path/$name" ]] || owned=0
    done
    ((owned)) || continue
    gateway_active_identity "$path/identity.sha256" >/dev/null || continue
    rm -R -- "$path" || return 1
  done
}

gateway_apply() {
  local platform="$1"
  local home share releases units config host_config pin_line version source_sha url archive_sha manifest_platform
  local stage artifact generation_name generation prior_current='' prior_previous='' prior_version=''
  local rollback_current='' rollback_previous='' rollback_version=''
  local current_identity='' previous_identity='' previous_version='' verified_runtime=''
  local unit_target runtime_identity unit_identity active_runtime='' active_unit=''
  local active_pair='' pair_state was_active=0 was_enabled=0 needs_activation=0
  local needs_unit_reload=0
  local preparation_status=0 credentials_installed=0 enablement_observation=0
  local service_observation=0 activation_failed=0
  local pointer_changed=0
  local saved_hup saved_int saved_term

  case "$platform" in
  macos) ;;
  arch | devbox)
    [[ "$dev_server_fleet_label_prefix" == dev.niels && "$gateway_port" == "$gateway_required_port" ]] ||
      die 'deployment identity on arch and devbox is the systemd user account'
    ;;
  *) die "unsupported gateway platform: $platform" ;;
  esac
  if gateway_pin_pending; then
    render_result ACTION "$gateway_name.release" 'published separated release pin is pending'
    return 2
  fi
  require_cmd curl jq tar python3
  gateway_validate_declared_inputs "$platform"
  pin_line="$(gateway_release_values "$platform")" || die 'gateway release pin is invalid'
  IFS=$'\t' read -r version source_sha url archive_sha manifest_platform <<<"$pin_line"

  home="$(dev_server_home)"
  if [[ -n "$gateway_provider_preflight" ]]; then
    "$gateway_provider_preflight" "$home" || return $?
  fi
  share="$home/.local/share/${gateway_name}"
  releases="$share/releases"
  units="$share/units"
  config="$home/.config/${gateway_name}"
  gateway_validate_protected_paths "$home"
  gateway_validate_namespace "$home" "$platform"
  if gateway_service_active "$platform"; then
    was_active=1
  else
    service_observation=$?
    ((service_observation == 1)) ||
      die 'could not observe gateway service activity'
  fi
  if gateway_service_enabled "$platform"; then
    was_enabled=1
  else
    enablement_observation=$?
    ((enablement_observation == 1)) ||
      die 'could not observe gateway service enablement'
  fi
  dev_server_directory_changed=0
  gateway_prepare_directories "$home" "$platform"
  if ((dev_server_directory_changed)); then
    render_result CHANGED "$gateway_name.directories" 'private directory topology installed'
  fi
  dev_server_acquire_lock "$share/.apply.lock" 9 gateway
  gateway_validate_local_state "$home"
  dev_server_remove_stale_stages "$share" ||
    die 'stale gateway staging state is invalid'
  gateway_validate_installed_generations "$home" ||
    die 'installed gateway generation topology is invalid'
  gateway_validate_installed_unit_generations "$home" ||
    die 'installed gateway unit generation topology is invalid'

  stage="$(mktemp -d "$share/.apply.stage.XXXXXX")" || die 'could not create gateway staging directory'
  chmod 0700 "$stage" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not secure the gateway staging directory'
  }
  saved_hup="$(trap -p HUP)"
  saved_int="$(trap -p INT)"
  saved_term="$(trap -p TERM)"
  trap 'dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true; exit 129' HUP
  trap 'dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true; exit 130' INT
  trap 'dev_server_remove_stage "$share" "$stage" >/dev/null 2>&1 || true; exit 143' TERM
  "$gateway_config_renderer" "$platform" "$stage" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not render gateway configuration'
  }
  host_config="$stage/host-config.json"
  artifact="$share/artifacts/$archive_sha"
  if gateway_prepare_artifact "$stage" "$version" "$source_sha" \
    "$url" "$archive_sha" "$manifest_platform" "$artifact"; then
    preparation_status=0
  else
    preparation_status=$?
  fi
  if ((preparation_status != 0)); then
    gateway_discard_stage "$share" "$stage"
    case "$preparation_status" in
    2) die 'gateway archive checksum differs from the release pin' ;;
    3) die 'gateway archive members are invalid' ;;
    4) die 'gateway release manifest differs from the release pin' ;;
    5) die 'gateway binary identity differs from the release pin' ;;
    6) die "gateway cached artifact is invalid: $artifact" ;;
    *) die 'could not prepare the gateway release' ;;
    esac
  fi

  # product schema belongs to the admitted binary; the shell kept only deployment facts.
  "$artifact/${gateway_name}" validate-host-config --host-config="$host_config" >/dev/null || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway host config is invalid'
  }
  if [[ -n "$gateway_provider_apply" ]]; then
    if "$gateway_provider_apply" "$home" "$stage"; then
      :
    else
      preparation_status=$?
      gateway_discard_stage "$share" "$stage"
      if ((preparation_status == 2)); then
        dev_server_restore_signal_trap HUP "$saved_hup"
        dev_server_restore_signal_trap INT "$saved_int"
        dev_server_restore_signal_trap TERM "$saved_term"
        exec 9>&-
        return 2
      fi
      die 'skid provider installation is incomplete'
    fi
  fi

  runtime_identity="$(gateway_runtime_identity "$artifact" "$host_config" "$stage/providers")" || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway runtime identity is invalid'
  }
  generation_name="$version-$runtime_identity"
  generation="$releases/$generation_name"
  if [[ -e "$generation" || -L "$generation" ]]; then
    if ! gateway_generation_exact "$artifact" "$generation" "$host_config" "$stage/providers"; then
      gateway_discard_stage "$share" "$stage"
      die 'immutable gateway generation differs from its admitted release'
    fi
  else
    mkdir -m 0700 "$stage/generation" &&
      install -m 0755 "$artifact/${gateway_name}" "$stage/generation/${gateway_name}" &&
      install -m 0644 "$artifact/characters.json" "$artifact/release.json" "$stage/generation/" &&
      install -m 0600 "$host_config" "$stage/generation/host-config.json" || {
      gateway_discard_stage "$share" "$stage"
      die 'could not stage the gateway generation'
    }
    if [[ "$gateway_name" == skidbladnir ]]; then
      mkdir -m 0700 "$stage/generation/providers" &&
        install -m 0755 "$stage/providers/native-control" "$stage/generation/providers/native-control" &&
        install -m 0755 "$stage/providers/provider-command" "$stage/generation/providers/provider-command" &&
        install -m 0644 "$stage/providers/shell-init" "$stage/generation/providers/shell-init" &&
        mkdir -m 0755 "$stage/generation/providers/claude-agent-identity" \
          "$stage/generation/providers/claude-agent-identity/.claude-plugin" \
          "$stage/generation/providers/claude-agent-identity/hooks" \
          "$stage/generation/providers/claude-agent-identity/bin" &&
        install -m 0644 "$stage/providers/claude-agent-identity/.claude-plugin/plugin.json" \
          "$stage/generation/providers/claude-agent-identity/.claude-plugin/plugin.json" &&
        install -m 0644 "$stage/providers/claude-agent-identity/hooks/hooks.json" \
          "$stage/generation/providers/claude-agent-identity/hooks/hooks.json" &&
        install -m 0755 "$stage/providers/claude-agent-identity/bin/agent-hook" \
          "$stage/generation/providers/claude-agent-identity/bin/agent-hook" || {
        gateway_discard_stage "$share" "$stage"
        die 'could not stage skid provider commands'
      }
    fi
    mv "$stage/generation" "$generation" || {
      gateway_discard_stage "$share" "$stage"
      die 'could not promote the gateway generation'
    }
    render_result INSTALLED "${gateway_receipt}.runtime" "$generation_name"
  fi

  if [[ -L "$share/current" ]]; then
    prior_current="$(readlink "$share/current")"
    prior_version="$(jq -er '.version' "$share/current/release.json")" || {
      gateway_discard_stage "$share" "$stage"
      die 'current gateway generation manifest is invalid'
    }
  fi
  if [[ -L "$share/previous" ]]; then
    prior_previous="$(readlink "$share/previous")"
  fi
  unit_target="$(gateway_unit_target "$platform" "$home")"
  dev_server_snapshot_file "$home/.local/bin/${gateway_name}-launch" "$stage/launcher-backup" 0755 || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway launcher target is invalid'
  }
  dev_server_snapshot_file "$unit_target" "$stage/unit-backup" 0644 || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway unit target is invalid'
  }

  if [[ ! -e "$config/deployment-identity" ]]; then
    printf '%s separated-v1\n' "$gateway_name" >"$stage/deployment-identity" || {
      gateway_discard_stage "$share" "$stage"
      die 'could not stage gateway deployment identity'
    }
    atomic_install_file "$stage/deployment-identity" "$config/deployment-identity" 0600 || {
      gateway_discard_stage "$share" "$stage"
      die 'could not record gateway deployment identity'
    }
  fi

  [[ -e "$config/machine-handle" || -L "$config/machine-handle" ]] || credentials_installed=1
  gateway_mint_secret "$generation/${gateway_name}" "$config/machine-handle" machine \
    '^mh-[0-9a-f]{32}$' || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway machine handle is invalid'
  }
  [[ -e "$config/bearer" || -L "$config/bearer" ]] || credentials_installed=1
  gateway_mint_secret "$generation/${gateway_name}" "$config/bearer" bearer \
    '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway bearer is invalid'
  }
  if ((credentials_installed)); then
    render_result INSTALLED "$gateway_name.credentials" 'machine handle and bearer minted'
  fi

  unit_identity="$(gateway_unit_identity "$platform")" || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway unit identity is invalid'
  }
  gateway_prepare_unit_generation "$platform" "$stage" "$units" "$unit_identity" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not preserve the desired gateway unit generation'
  }
  pair_state="$home/.local/state/dev-server/active/${gateway_receipt}.pair"
  if active_pair="$(gateway_active_pair "$pair_state")"; then
    IFS=' ' read -r active_runtime active_unit <<<"$active_pair"
  else
    [[ "$?" == 1 ]] || {
      gateway_discard_stage "$share" "$stage"
      die 'gateway active runtime and unit pair is invalid'
    }
  fi
  if [[ -n "$active_unit" ]]; then
    gateway_unit_generation_owned "$units/$active_unit" || {
      gateway_discard_stage "$share" "$stage"
      die 'recorded gateway unit generation is unavailable'
    }
  fi
  if [[ -n "$prior_current" ]]; then
    current_identity="$(gateway_runtime_identity "$share/$prior_current")" || {
      gateway_discard_stage "$share" "$stage"
      die 'current gateway runtime identity is invalid'
    }
  fi
  if [[ -n "$prior_previous" ]]; then
    previous_identity="$(gateway_runtime_identity "$share/$prior_previous")" || {
      gateway_discard_stage "$share" "$stage"
      die 'previous gateway runtime identity is invalid'
    }
    previous_version="$(jq -er '.version' "$share/$prior_previous/release.json")" || {
      gateway_discard_stage "$share" "$stage"
      die 'previous gateway generation manifest is invalid'
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
      gateway_discard_stage "$share" "$stage"
      die 'recorded active gateway runtime generation is unavailable'
    fi
  fi
  if ((was_active)) && [[ -n "$prior_current" ]]; then
    if gateway_running_binary_matches "$platform" "$home" "$prior_current"; then
      verified_runtime=current
    elif [[ -n "$prior_previous" ]] &&
      gateway_running_binary_matches "$platform" "$home" "$prior_previous"; then
      verified_runtime=previous
    fi
    if { [[ "$verified_runtime" == current ]] &&
      gateway_authenticated_health "$home" "$prior_version" "$platform" "$prior_current"; } ||
      { [[ "$verified_runtime" == previous ]] &&
        gateway_authenticated_health "$home" "$previous_version" "$platform" "$prior_previous"; }; then
      :
    else
      if [[ -n "$rollback_current" ]]; then
        if gateway_restore_runtime "$platform" "$home" "$stage" \
          "$rollback_current" "$rollback_previous" "$rollback_version" \
          "$unit_target" "$was_enabled" "$active_unit"; then
          :
        else
          gateway_settle_failed_restore "$share" "$stage" $?
          die 'unhealthy interrupted gateway activation could not restore the verified prior runtime'
        fi
        gateway_discard_stage "$share" "$stage"
        die 'unhealthy interrupted gateway activation; the verified prior runtime was restored'
      fi
      if [[ -z "$active_runtime" ]]; then
        if gateway_restore_runtime "$platform" "$home" "$stage" '' '' '' \
          "$unit_target" "$was_enabled" ''; then
          :
        else
          gateway_settle_failed_restore "$share" "$stage" $?
          die 'unverified gateway activation could not be removed safely'
        fi
        gateway_discard_stage "$share" "$stage"
        die 'unverified gateway first activation was stopped and unreferenced'
      fi
      gateway_discard_stage "$share" "$stage"
      die 'running gateway generation is not healthy enough for safe activation'
    fi
    # A healthy process started by an interrupted promotion is still uncommitted.
    # Only the atomic pair can authorize its runtime and unit as a rollback base.
    if [[ -n "$active_pair" ]]; then
      local observed_runtime observed_unit
      observed_runtime="$current_identity"
      [[ "$verified_runtime" != previous ]] || observed_runtime="$previous_identity"
      observed_unit="$(gateway_unit_files_identity "$home/.local/bin/${gateway_name}-launch" "$unit_target" 2>/dev/null || true)"
      if [[ "$observed_runtime" != "$active_runtime" || "$observed_unit" != "$active_unit" ]]; then
        if gateway_restore_runtime "$platform" "$home" "$stage" \
          "$rollback_current" "$rollback_previous" "$rollback_version" \
          "$unit_target" "$was_enabled" "$active_unit"; then
          gateway_discard_stage "$share" "$stage"
          die 'interrupted gateway activation; the verified runtime and unit pair was restored'
        else
          service_observation=$?
        fi
        gateway_settle_failed_restore "$share" "$stage" "$service_observation"
        die 'interrupted gateway activation could not restore its verified pair'
      fi
    fi
    if [[ -z "$active_pair" ]]; then
      # An interrupted first activation may be healthy, but it has never
      # committed a rollback authority. A failed retry returns to no runtime.
      rollback_current=''
      rollback_previous=''
      rollback_version=''
    elif [[ "$verified_runtime" == previous ]]; then
      rollback_current="$prior_previous"
      rollback_previous=''
      rollback_version="$previous_version"
    else
      rollback_current="$prior_current"
      rollback_previous="$prior_previous"
      rollback_version="$prior_version"
    fi
  fi

  gateway_install_runtime_files "$platform" "$home" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not install gateway unit inputs'
  }
  if [[ "$prior_current" != "releases/$generation_name" ]]; then
    if [[ "$rollback_current" == "releases/$generation_name" ]]; then
      dev_server_remove_link "$share/previous" || {
        gateway_discard_stage "$share" "$stage"
        die 'could not clear the duplicate gateway previous generation'
      }
    elif [[ -n "$rollback_current" ]]; then
      gateway_atomic_symlink "$share/previous" "$rollback_current" generation || {
        gateway_discard_stage "$share" "$stage"
        die 'could not set the prior gateway generation'
      }
    else
      dev_server_remove_link "$share/previous" || {
        gateway_discard_stage "$share" "$stage"
        die 'could not clear the prior gateway generation'
      }
    fi
    gateway_atomic_symlink "$share/current" "releases/$generation_name" generation || {
      gateway_discard_stage "$share" "$stage"
      die 'could not activate the gateway generation pointer'
    }
    pointer_changed=1
  fi

  if ((gateway_unit_changed)) || [[ "$active_unit" != "$unit_identity" ]]; then
    needs_unit_reload=1
  fi
  if ((was_active == 0 || pointer_changed != 0 || needs_unit_reload != 0)) ||
    [[ "$active_runtime" != "$runtime_identity" || "$verified_runtime" == previous ]]; then
    needs_activation=1
  fi
  activation_failed=0
  if ! gateway_activate_service "$platform" "$home" "$was_active" \
    "$needs_activation" "$needs_unit_reload"; then
    activation_failed=1
  elif ((needs_activation)); then
    if gateway_wait_for_active "$platform"; then
      gateway_authenticated_health "$home" "$version" "$platform" ||
        activation_failed=1
    else
      service_observation=$?
      if ((service_observation != 1)); then
        gateway_discard_stage "$share" "$stage"
        die 'gateway activation state could not be observed; active identity was not advanced'
      fi
      activation_failed=1
    fi
  fi
  if ((activation_failed)); then
    if gateway_restore_runtime "$platform" "$home" "$stage" "$rollback_current" \
      "$rollback_previous" "$rollback_version" "$unit_target" \
      "$was_enabled" "$active_unit"; then
      :
    else
      gateway_settle_failed_restore "$share" "$stage" $?
      die 'gateway activation failed and the prior runtime could not be restored'
    fi
    gateway_discard_stage "$share" "$stage"
    if [[ -n "$rollback_current" ]]; then
      die 'gateway activation failed; the verified prior runtime was restored'
    fi
    die 'gateway first activation failed; the candidate is inactive and unreferenced'
  fi
  ((pointer_changed == 0)) || render_result UPDATED "${gateway_receipt}.runtime" "$generation_name"
  ((gateway_unit_changed == 0)) ||
    render_result CHANGED "${gateway_receipt}.unit" 'launcher and service definition installed'
  if ((gateway_command_installed)); then
    if [[ "$gateway_name" == skidbladnir ]]; then
      render_result INSTALLED "$gateway_name.command" "commands available: $home/.local/bin/skid and skidbladnir"
    else
      render_result INSTALLED "$gateway_name.command" "$home/.local/bin/${gateway_name}"
    fi
  fi
  ((gateway_enablement_changed == 0)) ||
    render_result CHANGED "$gateway_name.enablement" 'enabled at login'
  [[ -z "$gateway_activation_status" ]] ||
    render_result "$gateway_activation_status" "${gateway_receipt}.runtime" "$version"
  dev_server_record_active_sha "${gateway_receipt}.runtime" "$runtime_identity" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not record the active gateway runtime identity'
  }
  dev_server_record_active_sha "${gateway_receipt}.unit" "$unit_identity" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not record the active gateway unit identity'
  }
  gateway_record_pair "$stage" "$home" "$runtime_identity" "$unit_identity" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not commit the verified gateway runtime and unit pair'
  }

  gateway_retain_generations "$home" || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway release retention found an unowned generation'
  }
  gateway_retain_unit_generations "$home" "$unit_identity" || {
    gateway_discard_stage "$share" "$stage"
    die 'gateway unit retention found an unowned generation'
  }
  gateway_retain_artifact "$artifact" || {
    gateway_discard_stage "$share" "$stage"
    die 'could not remove an obsolete gateway artifact cache'
  }
  gateway_discard_stage "$share" "$stage"
  dev_server_restore_signal_trap HUP "$saved_hup"
  dev_server_restore_signal_trap INT "$saved_int"
  dev_server_restore_signal_trap TERM "$saved_term"

  exec 9>&-
}

# Remove only a separated gateway. The old herdr-backed skid installation has
# no deployment marker and needs the explicit one-time handback procedure.
gateway_remove() {
  local platform="$1" home share config unit marker state enabled path name entries identity
  case "$platform" in
  macos | arch | devbox) ;;
  *) die "unsupported gateway platform: $platform" ;;
  esac
  home="$(dev_server_home)"
  share="$home/.local/share/$gateway_name"
  config="$home/.config/$gateway_name"
  marker="$config/deployment-identity"
  unit="$(gateway_unit_target "$platform" "$home")" || return 1
  gateway_validate_protected_paths "$home"
  gateway_validate_namespace "$home" "$platform"
  state="$(gateway_service_state "$platform")" || die "could not inspect $gateway_name service"
  if [[ ! -e "$marker" ]]; then
    [[ "$state" == absent ]] || die "$gateway_name service exists without separated deployment identity"
    for path in "$share/releases" "$share/artifacts" "$share/units"; do
      if [[ -d "$path" && -n "$(find "$path" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
        die "$gateway_name generations exist without separated deployment identity"
      fi
    done
    render_result 'UP TO DATE' "$gateway_name.removal" 'no separated gateway is installed'
    return 0
  fi
  [[ -d "$share" && ! -L "$share" ]] || die "$gateway_name data root is unavailable"
  dev_server_acquire_lock "$share/.apply.lock" 9 "$gateway_name"
  gateway_validate_local_state "$home"
  if compgen -G "$share/.apply.failed.*" >/dev/null; then
    die "$gateway_name has a retained failed-activation stage requiring inspection"
  fi
  dev_server_remove_stale_stages "$share" || die "invalid $gateway_name staging inventory"
  gateway_validate_installed_generations "$home" || die "invalid $gateway_name release inventory"
  gateway_validate_installed_unit_generations "$home" || die "invalid $gateway_name unit inventory"
  for path in "$home/.local/bin/$gateway_name-launch" "$unit"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -f "$path" && ! -L "$path" ]] || die "invalid $gateway_name service file: $path"
    fi
  done
  for path in "$config/client.json" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.pair" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.runtime.sha256" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.unit.sha256"; do
    if [[ -e "$path" || -L "$path" ]]; then
      [[ -f "$path" && ! -L "$path" && "$(file_mode "$path" 2>/dev/null)" == 600 ]] ||
        die "invalid $gateway_name private file: $path"
    fi
  done
  for path in "$share/artifacts"/*; do
    [[ -e "$path" || -L "$path" ]] || continue
    name="$(basename "$path")"
    [[ "$name" =~ ^[0-9a-f]{64}$ && -d "$path" && ! -L "$path" ]] ||
      die "unowned $gateway_name artifact: $path"
    entries="$(find "$path" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)" ||
      die "invalid $gateway_name artifact inventory"
    [[ "$entries" == "$(printf 'characters.json\nidentity.sha256\nrelease.json\n%s\n' "$gateway_name" | LC_ALL=C sort)" ]] ||
      die "unowned $gateway_name artifact: $path"
    identity="$(gateway_active_identity "$path/identity.sha256")" ||
      die "invalid $gateway_name artifact receipt"
    [[ "$(gateway_payload_hashes "$path" | dev_server_sha256_stream)" == "$identity" ]] ||
      die "modified $gateway_name artifact: $path"
  done
  if gateway_service_enabled "$platform"; then enabled=0; else enabled=$?; fi
  ((enabled <= 1)) || die "could not inspect $gateway_name enablement"
  gateway_stop_service "$platform" || die "could not stop $gateway_name service"
  if ((enabled == 0)); then
    if [[ "$platform" == macos ]]; then
      launchctl disable "gui/$(id -u)/$dev_server_fleet_label_prefix.$gateway_name" ||
        die "could not disable $gateway_name service"
    else
      systemctl --user disable "$gateway_name.service" ||
        die "could not disable $gateway_name service"
    fi
  fi
  dev_server_remove_link "$share/current" || die "could not remove $gateway_name current link"
  dev_server_remove_link "$share/previous" || die "could not remove $gateway_name previous link"
  dev_server_remove_link "$home/.local/bin/$gateway_name" || die "could not remove $gateway_name command link"
  if [[ "$gateway_name" == skidbladnir ]]; then
    dev_server_remove_link "$home/.local/bin/skid" || die 'could not remove skid command link'
    dev_server_remove_link "$home/.local/bin/skidbladnir-provider-runtime-control" ||
      die 'could not remove skid native helper link'
    dev_server_remove_link "$share/claude-agent-identity" ||
      die 'could not remove skid claude plugin link'
  fi
  for path in "$home/.local/bin/$gateway_name-launch" "$unit" \
    "$config/bearer" "$config/machine-handle" "$config/client.json" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.pair" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.runtime.sha256" \
    "$home/.local/state/dev-server/active/${gateway_receipt}.unit.sha256"; do
    [[ ! -e "$path" && ! -L "$path" ]] || rm -f -- "$path" ||
      die "could not remove $gateway_name owned file: $path"
  done
  for path in "$share/releases"/* "$share/artifacts"/* "$share/units"/*; do
    [[ ! -e "$path" && ! -L "$path" ]] || rm -R -- "$path" ||
      die "could not remove $gateway_name generation: $path"
  done
  rm -f -- "$marker" || die "could not clear $gateway_name deployment identity"
  if [[ "$platform" != macos ]]; then
    systemctl --user daemon-reload || die "could not reload $gateway_name service definitions"
  fi
  render_result CHANGED "$gateway_name.removal" 'separated gateway service, credentials, and generations removed'
  exec 9>&-
}
