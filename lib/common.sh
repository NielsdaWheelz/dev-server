#!/usr/bin/env bash

dev_server_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
dev_server_root="$(cd "$dev_server_lib_dir/.." && pwd -P)"
dev_server_home_dir="${dev_server_home_dir:-$HOME}"
dev_server_assets_root="${dev_server_assets_root:-$dev_server_root/assets}"

dev_server_changes='|'
dev_server_change_count=0
dev_server_result_mutations=0
dev_server_result_activations=0
dev_server_result_deferrals=0
dev_server_result_actions=0
dev_server_result_errors=0
dev_server_install_status='UP TO DATE'

log() {
  printf '%s\n' "$*"
}

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

dev_server_tmux_version_is_valid() {
  (($# == 1)) || return 1

  local LC_ALL=C
  local version="$1"

  [[ "$version" == 'tmux '* ]] || return 1
  version="${version#tmux }"
  ((${#version} >= 1 && ${#version} <= 60)) || return 1
  [[ "$version" =~ ^[!-~]+$ ]]
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

_dev_server_validate_change() {
  local change_id="$1"

  [[ "$change_id" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9_]*)+$ ]] ||
    die "invalid change identifier: $change_id"

  case "$change_id" in
  tmux.config | shell.config | desktop.session | ssh.config | docker.config | skid.unit | skid.runtime | skid.integration | tailscale.serve | system.reboot) ;;
  *) die "unregistered change identifier: $change_id" ;;
  esac
}

record_change() {
  (($# == 1)) || die 'record_change needs one change identifier'
  local change_id="$1"
  _dev_server_validate_change "$change_id"

  case "$dev_server_changes" in
  *"|$change_id|"*) return 0 ;;
  esac

  dev_server_changes="${dev_server_changes}${change_id}|"
  dev_server_change_count=$((dev_server_change_count + 1))
}

has_change() {
  (($# == 1)) || die 'has_change needs one change identifier'
  local change_id="$1"
  _dev_server_validate_change "$change_id"

  case "$dev_server_changes" in
  *"|$change_id|"*) return 0 ;;
  *) return 1 ;;
  esac
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

  if ! _dev_server_run "$privilege" test -f "$target" ||
    _dev_server_run "$privilege" test -L "$target"; then
    die "promoted managed target is invalid: $target"
  fi
  observed_mode="$(_dev_server_observed_mode "$privilege" "$target")" ||
    die "promoted managed target mode is unreadable: $target"
  if ! _dev_server_run "$privilege" cmp -s "$source" "$target" ||
    [[ "$observed_mode" != "$desired_mode" ]]; then
    die "promoted managed target failed verification: $target"
  fi

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

_dev_server_install_managed() {
  local privilege="$1"
  local source="$2"
  local target="$3"
  local mode="$4"
  local change_id="$5"

  _dev_server_validate_change "$change_id"
  _dev_server_atomic_install "$privilege" "$source" "$target" "$mode" || return 1
  case "$dev_server_install_status" in
  INSTALLED | UPDATED)
    record_change "$change_id"
    render_result "$dev_server_install_status" "$change_id" "$target"
    ;;
  UP\ TO\ DATE) ;;
  *) die "invalid atomic install result: $dev_server_install_status" ;;
  esac
}

install_managed_file() {
  (($# == 4)) || die 'install_managed_file needs source, target, mode, and change identifier'
  _dev_server_install_managed user "$@"
}

install_managed_file_as_root() {
  (($# == 4)) || die 'install_managed_file_as_root needs source, target, mode, and change identifier'
  _dev_server_install_managed root "$@"
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
