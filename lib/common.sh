#!/usr/bin/env bash

dev_server_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
dev_server_root="$(cd "$dev_server_lib_dir/.." && pwd -P)"
# deployment identity: the root of every installer-owned path, the launchd label
# prefix of the two fleet services (<prefix>.herdr, <prefix>.skidbladnir; never
# codex-shared) and the gateway's loopback port. fixed for a deployment's life;
# a second deployment on one mac is these three set differently.
dev_server_home_dir="${dev_server_home_dir:-$HOME}"
dev_server_fleet_label_prefix="${dev_server_fleet_label_prefix:-dev.niels}"
dev_server_gateway_port="${dev_server_gateway_port:-7341}"
dev_server_assets_root="${dev_server_assets_root:-$dev_server_root/assets}"

dev_server_result_mutations=0
dev_server_result_activations=0
dev_server_result_deferrals=0
dev_server_result_actions=0
dev_server_result_errors=0
dev_server_install_status='UP TO DATE'

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'ERROR  %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  (($# > 0)) || die 'require_cmd needs at least one command'

  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 ||
      die "missing required command: $command_name"
  done
}

dev_server_app_store_tailscale_cli() {
  (($# == 1)) || return 1

  local app="$1"
  local cli="$app/Contents/MacOS/Tailscale"
  local receipt="$app/Contents/_MASReceipt/receipt"

  [[ -d "$app" && ! -L "$app" &&
    -f "$cli" && ! -L "$cli" && -x "$cli" &&
    -f "$receipt" && ! -L "$receipt" ]] || return 1
  printf '%s\n' "$cli"
}

dev_server_tailscale_cli() {
  (($# == 0)) || return 1

  local cli
  if cli="$(type -P tailscale 2>/dev/null)" && [[ -n "$cli" ]]; then
    printf '%s\n' "$cli"
    return 0
  fi
  dev_server_app_store_tailscale_cli /Applications/Tailscale.app
}

dev_server_sha256() {
  (($# == 1)) || die 'dev_server_sha256 needs one file'
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] ||
    die "SHA-256 input is not a regular file: $path"

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    die 'missing SHA-256 command: install sha256sum or shasum'
  fi
}

dev_server_sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die 'missing SHA-256 command: install sha256sum or shasum'
  fi
}

dev_server_assets_dir() {
  printf '%s\n' "$dev_server_assets_root"
}

dev_server_home() {
  printf '%s\n' "$dev_server_home_dir"
}

# the macbook assets name the deployment identity as @ROOT@, @FLEET_LABEL_PREFIX@
# and @GATEWAY_PORT@; every other asset is literal. DIR is a private copy of
# assets/: the four templates are rendered in place and the libraries read that copy.
dev_server_render_assets() {
  (($# == 1)) || die 'dev_server_render_assets needs one private assets directory'
  local assets="$1"
  local path rendered

  [[ "$dev_server_home_dir" =~ ^/[A-Za-z0-9._/-]+$ ]] ||
    die "invalid deployment root: $dev_server_home_dir"
  [[ "$dev_server_fleet_label_prefix" =~ ^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)*$ ]] ||
    die "invalid fleet label prefix: $dev_server_fleet_label_prefix"
  [[ "$dev_server_gateway_port" =~ ^[1-9][0-9]{0,4}$ ]] || die "invalid gateway port: $dev_server_gateway_port"
  ((dev_server_gateway_port <= 65535)) || die "invalid gateway port: $dev_server_gateway_port"
  [[ -d "$assets" && ! -L "$assets" ]] || die "rendered assets directory is invalid: $assets"
  for path in \
    herdr/dev.niels.herdr.plist \
    skidbladnir/dev.niels.skidbladnir.plist \
    skidbladnir/host-config-macbook.json \
    skidbladnir/agent-hooks-macbook.json; do
    path="$assets/$path"
    [[ -f "$path" && ! -L "$path" ]] || die "invalid asset template: $path"
    rendered="$(LC_ALL=C sed \
      -e "s|@ROOT@|$dev_server_home_dir|g" \
      -e "s|@FLEET_LABEL_PREFIX@|$dev_server_fleet_label_prefix|g" \
      -e "s|@GATEWAY_PORT@|$dev_server_gateway_port|g" "$path" && printf .)" ||
      die "could not render asset template: $path"
    printf '%s' "${rendered%.}" >"$path" || die "could not write rendered asset: $path"
    ! LC_ALL=C grep -Eq '@[A-Z_]+@' "$path" || die "unrendered placeholder in asset: $path"
  done
  dev_server_assets_root="$assets"
  # Read dynamically by the already-sourced Skidbladnir library.
  # shellcheck disable=SC2034
  skidbladnir_release_pin_file="$assets/skidbladnir/release-pin.json"
}

dev_server_declared_snapshot() {
  (($# >= 2)) || die 'dev_server_declared_snapshot needs a root and declared paths'
  local root="$1"
  shift

  require_cmd python3
  [[ -d "$root" && ! -L "$root" ]] ||
    die "declared input root is not a regular directory: $root"
  python3 - "$root" "$@" <<'PY' ||
import hashlib
import os
import stat
import sys

root = os.path.abspath(sys.argv[1])
digest = hashlib.sha256()
seen = set()

def add_file(path, relative, metadata):
    if relative in seen:
        raise SystemExit(f"duplicate declared input: {relative}")
    seen.add(relative)
    encoded = relative.encode("utf-8")
    mode = stat.S_IMODE(metadata.st_mode)
    size = metadata.st_size
    digest.update(len(encoded).to_bytes(8, "big"))
    digest.update(encoded)
    digest.update(mode.to_bytes(4, "big"))
    digest.update(size.to_bytes(8, "big"))
    with open(path, "rb") as stream:
        while True:
            chunk = stream.read(1024 * 1024)
            if not chunk:
                break
            digest.update(chunk)

def visit(path, relative):
    metadata = os.stat(path, follow_symlinks=False)
    if stat.S_ISLNK(metadata.st_mode):
        raise SystemExit(f"declared input is a symlink: {relative}")
    if stat.S_ISREG(metadata.st_mode):
        add_file(path, relative, metadata)
        return
    if not stat.S_ISDIR(metadata.st_mode):
        raise SystemExit(f"declared input has an unsupported type: {relative}")
    with os.scandir(path) as entries:
        children = sorted(entries, key=lambda item: item.name.encode("utf-8"))
    for child in children:
        child_relative = f"{relative}/{child.name}" if relative else child.name
        visit(child.path, child_relative)

for declared in sys.argv[2:]:
    if (not declared or os.path.isabs(declared) or declared in (".", "..") or
            any(part in ("", ".", "..") for part in declared.split("/"))):
        raise SystemExit(f"invalid declared input path: {declared}")
    path = os.path.join(root, declared)
    if not os.path.lexists(path):
        raise SystemExit(f"declared input is missing: {declared}")
    visit(path, declared)

print(digest.hexdigest())
PY
    die 'could not fingerprint declared inputs'
}

_dev_server_print_result() {
  local status="$1"
  local subject="$2"
  shift 2

  printf '%s  %s' "$status" "$subject"
  if (($# > 0)); then
    printf ': %s' "$*"
  fi
  printf '\n'
}

render_result() {
  (($# >= 2)) || die 'render_result needs a status and subject'

  local status="$1"
  local subject="$2"
  shift 2
  [[ -n "$subject" && "$subject" != *$'\n'* ]] ||
    die 'result subject must be one nonempty line'
  local detail
  for detail in "$@"; do
    [[ "$detail" != *$'\n'* ]] || die 'result detail must be one line'
  done

  case "$status" in
  INSTALLED | UPDATED | CHANGED)
    dev_server_result_mutations=$((dev_server_result_mutations + 1))
    ;;
  STARTED | RELOADED | RESTARTED)
    dev_server_result_activations=$((dev_server_result_activations + 1))
    ;;
  DEFERRED)
    dev_server_result_deferrals=$((dev_server_result_deferrals + 1))
    ;;
  ACTION)
    dev_server_result_actions=$((dev_server_result_actions + 1))
    ;;
  UP\ TO\ DATE) ;;
  ERROR)
    dev_server_result_errors=$((dev_server_result_errors + 1))
    ;;
  *) die "invalid result status: $status" ;;
  esac

  _dev_server_print_result "$status" "$subject" "$@"
}

finish_results() {
  (($# == 1)) || die 'finish_results needs one target name'

  local target="$1"
  local detail
  [[ -n "$target" && "$target" != *$'\n'* ]] ||
    die 'summary target must be one nonempty line'

  if ((dev_server_result_errors > 0)); then
    detail="$dev_server_result_errors error(s)"
    ((dev_server_result_actions == 0)) || detail="$detail, $dev_server_result_actions action(s)"
    _dev_server_print_result ERROR "$target" "$detail"
    return 1
  fi

  if ((dev_server_result_actions > 0)); then
    detail="$dev_server_result_actions user action(s) required"
    ((dev_server_result_mutations == 0)) || detail="$detail, $dev_server_result_mutations durable change(s) installed"
    ((dev_server_result_activations == 0)) || detail="$detail, $dev_server_result_activations activation(s)"
    ((dev_server_result_deferrals == 0)) || detail="$detail, $dev_server_result_deferrals deferral(s)"
    _dev_server_print_result ACTION "$target" "$detail"
    return 2
  fi

  if ((dev_server_result_mutations > 0 || dev_server_result_activations > 0)); then
    detail="$dev_server_result_mutations durable change(s), $dev_server_result_activations activation(s)"
    ((dev_server_result_deferrals == 0)) || detail="$detail, $dev_server_result_deferrals deferral(s)"
    _dev_server_print_result UPDATED "$target" "$detail"
    return 0
  fi

  if ((dev_server_result_deferrals > 0)); then
    _dev_server_print_result DEFERRED "$target" "$dev_server_result_deferrals deferral(s); durable state installed"
    return 0
  fi

  _dev_server_print_result 'UP TO DATE' "$target"
}

_dev_server_normalize_mode() {
  case "$1" in
  0[0-7][0-7][0-7]) printf '%s\n' "${1#0}" ;;
  [0-7][0-7][0-7]) printf '%s\n' "$1" ;;
  *) return 1 ;;
  esac
}

_dev_server_run() {
  local privilege="$1"
  shift

  case "$privilege" in
  user) "$@" ;;
  root) sudo -- "$@" ;;
  *) die "invalid install privilege: $privilege" ;;
  esac
}

_dev_server_observed_mode() {
  local privilege="$1"
  local path="$2"
  local mode

  mode="$(_dev_server_run "$privilege" stat -c '%a' "$path" 2>/dev/null)" ||
    mode="$(_dev_server_run "$privilege" stat -f '%Lp' "$path" 2>/dev/null)" ||
    return 1
  _dev_server_normalize_mode "$mode"
}

file_mode() {
  (($# == 1)) || die 'file_mode needs one file'
  local path="$1"
  [[ -f "$path" && ! -L "$path" ]] ||
    die "mode input is not a regular non-symlink file: $path"
  _dev_server_observed_mode user "$path" || die "file mode is unreadable: $path"
}

dev_server_active_dir() {
  printf '%s/.local/state/dev-server/active\n' "$(dev_server_home)"
}

_dev_server_validate_active_consumer() {
  [[ "$1" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9_]*)*$ ]] ||
    die "invalid active identity consumer: $1"
}

dev_server_validate_active_sha() {
  local consumer="$1"
  local path

  _dev_server_validate_active_consumer "$consumer"
  path="$(dev_server_active_dir)/$consumer.sha256"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -f "$path" && ! -L "$path" ]] || die "invalid active identity: $path"
  [[ "$(file_mode "$path")" == 600 ]] || die "invalid active identity mode: $path"
  [[ "$(LC_ALL=C wc -c <"$path" | tr -d '[:space:]')" == 65 ]] ||
    die "invalid active identity length: $path"
  grep -Eq '^[0-9a-f]{64}$' "$path" || die "invalid active identity content: $path"
}

dev_server_active_sha_matches() {
  local consumer="$1"
  local desired_sha="$2"
  local path

  [[ "$desired_sha" =~ ^[0-9a-f]{64}$ ]] ||
    die "invalid desired active identity: $consumer"
  dev_server_validate_active_sha "$consumer"
  path="$(dev_server_active_dir)/$consumer.sha256"
  [[ -f "$path" ]] && [[ "$(<"$path")" == "$desired_sha" ]]
}

dev_server_record_active_sha() (
  local consumer="$1"
  local desired_sha="$2"
  local path temporary=''

  _dev_server_validate_active_consumer "$consumer"
  [[ "$desired_sha" =~ ^[0-9a-f]{64}$ ]] ||
    die "invalid desired active identity: $consumer"
  path="$(dev_server_active_dir)/$consumer.sha256"
  [[ -d "$(dirname "$path")" && ! -L "$(dirname "$path")" ]] ||
    die "active identity directory does not exist: $(dirname "$path")"
  cleanup_active_stage() {
    [[ -z "$temporary" ]] || rm -f -- "$temporary"
  }
  trap cleanup_active_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM
  temporary="$(mktemp "$(dirname "$path")/.$consumer.sha256.input.XXXXXX")" ||
    die "could not stage active identity: $consumer"
  printf '%s\n' "$desired_sha" >"$temporary" ||
    die "could not write active identity: $consumer"
  chmod 0600 "$temporary" || die "could not secure active identity: $consumer"
  atomic_install_file "$temporary" "$path" 0600 || return 1
)

dev_server_prepare_active_dir() {
  local home

  home="$(dev_server_home)"
  ensure_directory "$home/.local" 0755 >/dev/null || return 1
  ensure_directory "$home/.local/state" 0755 >/dev/null || return 1
  ensure_directory "$home/.local/state/dev-server" 0700 >/dev/null || return 1
  ensure_directory "$(dev_server_active_dir)" 0700 >/dev/null || return 1
}

_dev_server_atomic_install_impl() (
  local privilege="$1"
  local source="$2"
  local target="$3"
  local requested_mode="$4"
  local desired_mode observed_mode target_dir target_name status
  _dev_server_staging=''
  _dev_server_staging_privilege="$privilege"

  desired_mode="$(_dev_server_normalize_mode "$requested_mode")" ||
    die "invalid file mode: $requested_mode"
  [[ -f "$source" && ! -L "$source" ]] ||
    die "managed source is not a regular non-symlink file: $source"
  [[ -n "$target" ]] || die 'managed target path is empty'

  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"
  [[ "$target_name" != . && "$target_name" != .. ]] ||
    die "managed target path is invalid: $target"
  _dev_server_run "$privilege" test -d "$target_dir" ||
    die "managed target directory does not exist: $target_dir"

  if _dev_server_run "$privilege" test -L "$target"; then
    die "managed target is a symlink: $target"
  fi

  if _dev_server_run "$privilege" test -e "$target"; then
    _dev_server_run "$privilege" test -f "$target" ||
      die "managed target is not a regular file: $target"
    observed_mode="$(_dev_server_observed_mode "$privilege" "$target")" ||
      die "managed target mode is unreadable: $target"
    if _dev_server_run "$privilege" cmp -s "$source" "$target" &&
      [[ "$observed_mode" == "$desired_mode" ]]; then
      printf 'UP TO DATE\n'
      exit 0
    fi
    status=UPDATED
  else
    status=INSTALLED
  fi

  cleanup_staging() {
    if [[ -n "${_dev_server_staging:-}" ]]; then
      _dev_server_run "${_dev_server_staging_privilege:-user}" rm -f "$_dev_server_staging" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup_staging EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  _dev_server_staging="$(_dev_server_run "$privilege" mktemp "$target_dir/.${target_name}.dev-server.XXXXXX")" ||
    die "could not stage managed target: $target"
  if ! _dev_server_run "$privilege" test -f "$_dev_server_staging" ||
    _dev_server_run "$privilege" test -L "$_dev_server_staging"; then
    die "managed staging file is invalid: $_dev_server_staging"
  fi

  _dev_server_run "$privilege" install -m "0$desired_mode" "$source" "$_dev_server_staging" ||
    die "could not populate managed staging file: $target"
  observed_mode="$(_dev_server_observed_mode "$privilege" "$_dev_server_staging")" ||
    die "managed staging mode is unreadable: $target"
  if ! _dev_server_run "$privilege" cmp -s "$source" "$_dev_server_staging" ||
    [[ "$observed_mode" != "$desired_mode" ]]; then
    die "managed staging file failed verification: $target"
  fi

  _dev_server_run "$privilege" mv -f "$_dev_server_staging" "$target" ||
    die "could not promote managed target: $target"
  _dev_server_staging=''

  printf '%s\n' "$status"
)

_dev_server_atomic_install() {
  local privilege="$1"
  shift
  (($# == 3)) || die 'atomic_install_file needs source, target, and mode'
  [[ "$privilege" != root ]] || require_cmd sudo

  dev_server_install_status="$(_dev_server_atomic_install_impl "$privilege" "$@")" || return 1
}

atomic_install_file() {
  _dev_server_atomic_install user "$@"
}

atomic_install_file_as_root() {
  _dev_server_atomic_install root "$@"
}

install_managed_file() {
  (($# == 4)) || die 'install_managed_file needs source, target, mode, and result subject'
  local source="$1"
  local target="$2"
  local mode="$3"
  local subject="$4"

  atomic_install_file "$source" "$target" "$mode" || return 1
  case "$dev_server_install_status" in
  INSTALLED | UPDATED)
    render_result "$dev_server_install_status" "$subject" "$target"
    ;;
  UP\ TO\ DATE) ;;
  *) die "invalid atomic install result: $dev_server_install_status" ;;
  esac
}

_dev_server_ensure_directory_impl() (
  local privilege="$1"
  local path="$2"
  local requested_mode="$3"
  local desired_mode observed_mode parent status

  desired_mode="$(_dev_server_normalize_mode "$requested_mode")" ||
    die "invalid directory mode: $requested_mode"
  [[ -n "$path" && "$path" != / && "$path" != */ ]] ||
    die "managed directory path is invalid: $path"

  parent="$(dirname "$path")"
  _dev_server_run "$privilege" test -d "$parent" ||
    die "managed directory parent does not exist: $parent"

  if _dev_server_run "$privilege" test -L "$path"; then
    die "managed directory is a symlink: $path"
  fi

  if _dev_server_run "$privilege" test -e "$path"; then
    _dev_server_run "$privilege" test -d "$path" ||
      die "managed directory is not a directory: $path"
    observed_mode="$(_dev_server_observed_mode "$privilege" "$path")" ||
      die "managed directory mode is unreadable: $path"
    if [[ "$observed_mode" == "$desired_mode" ]]; then
      printf 'UP TO DATE\n'
      exit 0
    fi
    _dev_server_run "$privilege" chmod "0$desired_mode" "$path" ||
      die "could not set managed directory mode: $path"
    status=UPDATED
  else
    _dev_server_run "$privilege" mkdir -m "0$desired_mode" "$path" ||
      die "could not create managed directory: $path"
    status=INSTALLED
  fi

  if ! _dev_server_run "$privilege" test -d "$path" ||
    _dev_server_run "$privilege" test -L "$path"; then
    die "managed directory is invalid after reconciliation: $path"
  fi
  observed_mode="$(_dev_server_observed_mode "$privilege" "$path")" ||
    die "managed directory mode is unreadable after reconciliation: $path"
  if [[ "$status" == INSTALLED && "$observed_mode" != "$desired_mode" ]]; then
    _dev_server_run "$privilege" chmod "0$desired_mode" "$path" ||
      die "could not set new managed directory mode: $path"
    observed_mode="$(_dev_server_observed_mode "$privilege" "$path")" ||
      die "new managed directory mode is unreadable: $path"
  fi
  [[ "$observed_mode" == "$desired_mode" ]] ||
    die "managed directory mode differs after reconciliation: $path"
  printf '%s\n' "$status"
)

_dev_server_ensure_directory() {
  local privilege="$1"
  shift
  (($# == 2)) || die 'ensure_directory needs path and mode'
  [[ "$privilege" != root ]] || require_cmd sudo

  dev_server_install_status="$(_dev_server_ensure_directory_impl "$privilege" "$@")" || return 1
  case "$dev_server_install_status" in
  INSTALLED | UPDATED) render_result "$dev_server_install_status" "$1" ;;
  UP\ TO\ DATE) ;;
  *) die "invalid directory reconciliation result: $dev_server_install_status" ;;
  esac
}

ensure_directory() {
  _dev_server_ensure_directory user "$@"
}

ensure_directory_as_root() {
  _dev_server_ensure_directory root "$@"
}

dev_server_strict_json_file() {
  local path="$1"
  local maximum_bytes="$2"

  python3 - "$path" "$maximum_bytes" <<'PY'
import json
import os
import stat
import sys

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result

def reject_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")

path, maximum = sys.argv[1], int(sys.argv[2])
mode = os.lstat(path).st_mode
if not stat.S_ISREG(mode):
    raise SystemExit(1)
with open(path, "rb") as stream:
    encoded = stream.read(maximum + 1)
if not encoded or len(encoded) > maximum:
    raise SystemExit(1)
json.loads(encoded.decode("utf-8"), object_pairs_hook=unique_object,
           parse_constant=reject_constant)
PY
}

dev_server_download() {
  (($# == 2)) || die 'dev_server_download needs a url and an output path'
  curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
    --output "$2" "$1"
}

dev_server_acquire_lock() {
  (($# == 3)) || die 'dev_server_acquire_lock needs a lock path, a descriptor, and a name'
  local lock="$1"
  local descriptor="$2"
  local name="$3"

  [[ "$descriptor" =~ ^[3-9]$ ]] || die "invalid lock descriptor: $descriptor"
  [[ ! -L "$lock" && (! -e "$lock" || -f "$lock") ]] ||
    die "$name apply lock is invalid"
  eval "exec $descriptor>>\"\$lock\"" || die "could not open the $name apply lock"
  chmod 0600 "$lock" || die "could not secure the $name apply lock"
  case "$(uname -s)" in
  Darwin)
    require_cmd lockf
    lockf -s -t 0 "$descriptor" || die "$name apply is already running"
    ;;
  Linux)
    require_cmd flock
    flock -n "$descriptor" || die "$name apply is already running"
    ;;
  *) die "$name locking is unsupported on this platform" ;;
  esac
}

dev_server_remove_stage() {
  local share="$1"
  local stage="$2"
  local name

  [[ "$(dirname "$stage")" == "$share" ]] || return 1
  name="$(basename "$stage")"
  [[ "$name" =~ ^\.apply\.stage\.[A-Za-z0-9]{6}$ ]] || return 1
  [[ -d "$stage" && ! -L "$stage" ]] || return 1
  rm -R -- "$stage"
}

# keeps a stage whose backups are still the only copy of the prior inputs,
# under a name the stale-stage sweep leaves alone. prints the new path.
dev_server_retain_stage() {
  local share="$1"
  local stage="$2"
  local retained="$share/.apply.failed.${stage##*.}"

  [[ "$(dirname "$stage")" == "$share" && ! -e "$retained" ]] || return 1
  mv "$stage" "$retained" || return 1
  printf '%s\n' "$retained"
}

dev_server_remove_stale_stages() {
  local share="$1"
  local stage
  local -a stages=()

  shopt -s nullglob
  stages=("$share"/.apply.stage.*)
  shopt -u nullglob
  if ((${#stages[@]} > 0)); then
    for stage in "${stages[@]}"; do
      dev_server_remove_stage "$share" "$stage" || return 1
    done
  fi
}

dev_server_replace_path() {
  python3 - "$1" "$2" <<'PY'
import os
import sys

os.replace(sys.argv[1], sys.argv[2])
PY
}

dev_server_atomic_symlink() (
  local target="$1"
  local relative="$2"
  local directory name temporary=''
  local attempt

  dev_server_symlink_stage_cleanup() {
    if [[ -n "$temporary" && "$(dirname "$temporary")" == "$directory" &&
    "$(basename "$temporary")" == ".${name}.dev-server."* &&
    -L "$temporary" ]]; then
      rm -f -- "$temporary"
    fi
  }
  trap dev_server_symlink_stage_cleanup EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  if [[ -e "$target" || -L "$target" ]]; then
    [[ -L "$target" ]] || return 1
    if [[ "$(readlink "$target")" == "$relative" ]]; then
      return 0
    fi
  fi
  directory="$(dirname "$target")"
  name="$(basename "$target")"
  for attempt in {1..32}; do
    temporary="$directory/.$name.dev-server.$$.$RANDOM.$attempt"
    if ln -s "$relative" "$temporary" 2>/dev/null; then
      break
    fi
    temporary=''
  done
  [[ -n "$temporary" ]] || return 1
  if [[ ! -L "$temporary" || "$(readlink "$temporary")" != "$relative" ]]; then
    rm -f -- "$temporary"
    return 1
  fi
  if ! dev_server_replace_path "$temporary" "$target"; then
    rm -f -- "$temporary"
    return 1
  fi
  [[ -L "$target" && "$(readlink "$target")" == "$relative" ]]
)

dev_server_remove_link() {
  local target="$1"
  if [[ ! -e "$target" && ! -L "$target" ]]; then
    return 0
  fi
  [[ -L "$target" ]] || return 1
  rm -f -- "$target"
}

dev_server_snapshot_file() {
  local target="$1"
  local snapshot="$2"
  local mode="$3"

  if [[ ! -e "$target" && ! -L "$target" ]]; then
    : >"$snapshot.absent"
    return
  fi
  [[ -f "$target" && ! -L "$target" ]] || return 1
  install -m "$mode" "$target" "$snapshot"
  : >"$snapshot.present"
}

dev_server_restore_file() {
  local target="$1"
  local snapshot="$2"
  local mode="$3"

  if [[ -f "$snapshot.present" && ! -L "$snapshot.present" &&
    ! -e "$snapshot.absent" ]]; then
    atomic_install_file "$snapshot" "$target" "$mode"
  elif [[ -f "$snapshot.absent" && ! -L "$snapshot.absent" &&
    ! -e "$snapshot.present" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
      [[ -f "$target" && ! -L "$target" ]] || return 1
      rm -f -- "$target"
    fi
  else
    return 1
  fi
}

# user service observation. NAME is the launchd label on macos and the unit
# name on arch/devbox. states: absent, inactive, active; return 2 when the
# supervisor's answer cannot be read.
dev_server_service_state() {
  local platform="$1"
  local name="$2"
  local output rc line state='' matches=0
  local launchd_state_pattern=$'^\tstate[[:space:]]=[[:space:]]([A-Za-z][A-Za-z[:space:]-]{0,63})$'

  case "$platform" in
  arch | devbox)
    if output="$(systemctl --user is-active "$name" 2>/dev/null)"; then
      rc=0
    else
      rc=$?
    fi
    # a starting, stopping or reloading server still owns its inputs and socket.
    case "$output" in
    active | activating | deactivating | reloading)
      printf '%s\n' active
      return 0
      ;;
    esac
    case "$rc" in
    3) printf '%s\n' inactive ;;
    4) printf '%s\n' absent ;;
    *) return 2 ;;
    esac
    ;;
  macos)
    if output="$(launchctl print "gui/$(id -u)/$name" 2>/dev/null)"; then
      rc=0
    else
      rc=$?
    fi
    if ((rc == 113)); then
      printf '%s\n' absent
      return 0
    fi
    ((rc == 0 && ${#output} <= 65536)) || return 2
    while IFS= read -r line; do
      [[ "$line" == $'\tstate = '* ]] || continue
      [[ "$line" =~ $launchd_state_pattern ]] || return 2
      matches=$((matches + 1))
      state="${BASH_REMATCH[1]}"
    done <<<"$output"
    ((matches == 1)) || return 2
    # a job launchd is still spawning (xpcproxy) or tearing down (SIGTERMed)
    # owns its inputs and socket like a running one.
    case "$state" in
    running | 'spawn scheduled' | xpcproxy | SIGTERMed) printf '%s\n' active ;;
    *) printf '%s\n' inactive ;;
    esac
    ;;
  *) return 2 ;;
  esac
}

# stops a user service and returns only when its supervisor has finished tearing
# it down: launchctl bootout returns while the job is still exiting, and a
# bootstrap in that window fails with EIO. the observed state decides, not the
# stop command's exit. 0 stopped or already absent; 1 still there afterwards
# (thirty seconds on macos, past ExitTimeOut and launchd's SIGKILL).
dev_server_stop_service() {
  local platform="$1"
  local name="$2"
  local state deadline

  state="$(dev_server_service_state "$platform" "$name")" || return 1
  [[ "$state" != absent ]] || return 0
  case "$platform" in
  arch | devbox)
    systemctl --user stop "$name" >/dev/null 2>&1 || true
    state="$(dev_server_service_state "$platform" "$name")" || return 1
    [[ "$state" != active ]]
    ;;
  macos)
    launchctl bootout "gui/$(id -u)/$name" >/dev/null 2>&1 || true
    deadline=$((SECONDS + 30))
    while :; do
      if state="$(dev_server_service_state "$platform" "$name")"; then
        [[ "$state" != absent ]] || return 0
      fi
      ((SECONDS < deadline)) || return 1
      sleep 1
    done
    ;;
  *) return 1 ;;
  esac
}

# ensure_directory without its per-directory line; callers render one aggregate.
dev_server_directory_changed=0
# shellcheck disable=SC2034 # read by the libraries that aggregate directory changes.
dev_server_reconcile_directory() {
  local output
  output="$(ensure_directory "$1" "$2")" || return 1
  [[ -z "$output" ]] || dev_server_directory_changed=1
}

dev_server_restore_signal_trap() {
  local signal="$1"
  local saved="$2"

  if [[ -n "$saved" ]]; then
    # shellcheck disable=SC2294 # trap -p emits the shell-escaped restoration command.
    eval "$saved"
  else
    trap - "$signal"
  fi
}

dev_server_service_enabled() {
  local platform="$1"
  local name="$2"
  local disabled line rc value=''
  local matches=0
  local pattern="^[[:space:]]*\"${name//./[.]}\"[[:space:]]*=>[[:space:]]*(enabled|disabled),?[[:space:]]*$"

  case "$platform" in
  macos)
    disabled="$(launchctl print-disabled "gui/$(id -u)" 2>/dev/null)" || return 2
    ((${#disabled} <= 65536)) || return 2
    while IFS= read -r line; do
      [[ "$line" == *"\"$name\""* ]] || continue
      [[ "$line" =~ $pattern ]] || return 2
      matches=$((matches + 1))
      value="${BASH_REMATCH[1]}"
    done <<<"$disabled"
    ((matches <= 1)) || return 2
    [[ "$value" != disabled ]]
    ;;
  arch | devbox)
    if systemctl --user is-enabled --quiet "$name"; then
      return 0
    else
      rc=$?
    fi
    case "$rc" in
    1 | 4) return 1 ;;
    *) return 2 ;;
    esac
    ;;
  *) return 1 ;;
  esac
}

dev_server_service_main_pid() {
  local platform="$1"
  local name="$2"
  local pid

  case "$platform" in
  arch | devbox)
    pid="$(systemctl --user show "$name" --property MainPID --value 2>/dev/null)" || return 1
    ;;
  macos)
    pid="$(launchctl print "gui/$(id -u)/$name" 2>/dev/null |
      LC_ALL=C awk '$1 == "pid" && $2 == "=" && $3 ~ /^[1-9][0-9]*$/ {print $3}')"
    ;;
  *) return 1 ;;
  esac
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$pid"
}
