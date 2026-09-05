#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=../lib/common.sh
source "$repo_dir/lib/common.sh"

tests_run=0
fixture=''

fail() {
  printf 'FAIL  helpers: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "$actual" == "$expected" ]] ||
    fail "$label: expected <$expected>, got <$actual>"
}

assert_contains() {
  local path="$1"
  local expected="$2"
  local label="$3"
  grep -F -- "$expected" "$path" >/dev/null ||
    fail "$label: <$expected> not found in $path"
}

assert_mode() {
  local expected="${1#0}"
  local path="$2"
  local label="$3"
  assert_eq "$expected" "$(_dev_server_observed_mode user "$path")" "$label"
}

write_executable() {
  local path="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' "$@" >"$path"
  chmod 0755 "$path"
}

run_test() {
  local name="$1"
  "$name"
  tests_run=$((tests_run + 1))
}

cleanup() {
  [[ -n "$fixture" ]] || return 0
  case "$fixture" in
  "${TMPDIR:-/tmp}"/dev-server-helpers.*)
    chmod -R u+rwX "$fixture" 2>/dev/null || true
    rm -rf -- "$fixture"
    ;;
  *)
    printf 'ERROR  refusing to clean unexpected test path: %s\n' "$fixture" >&2
    return 1
    ;;
  esac
}

test_sha_contract() (
  local dir="$fixture/sha"
  mkdir "$dir"
  : >"$dir/empty"
  assert_eq \
    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
    "$(dev_server_sha256 "$dir/empty")" \
    'file SHA-256'
  assert_eq \
    e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855 \
    "$(printf '' | dev_server_sha256_stream)" \
    'stream SHA-256'

  ln -s empty "$dir/link"
  if (dev_server_sha256 "$dir/link") >"$dir/output" 2>&1; then
    fail 'SHA-256 accepted a symlink'
  fi
  assert_contains "$dir/output" 'ERROR  SHA-256 input is not a regular file' 'symlink SHA rejection'
)

test_declared_snapshot_contract() (
  local dir="$fixture/declared-snapshot"
  local initial mode_changed restored

  mkdir -p "$dir/assets/nested" "$dir/packages"
  printf 'declared bytes\n' >"$dir/assets/nested/input"
  printf 'package\n' >"$dir/packages/manifest"
  chmod 0644 "$dir/assets/nested/input" "$dir/packages/manifest"

  initial="$(
    dev_server_declared_snapshot "$dir" assets packages/manifest
  )"
  chmod 0600 "$dir/assets/nested/input"
  mode_changed="$(
    dev_server_declared_snapshot "$dir" assets packages/manifest
  )"
  [[ "$mode_changed" != "$initial" ]] ||
    fail 'declared snapshot ignored a regular-file mode change'

  chmod 0644 "$dir/assets/nested/input"
  restored="$(
    dev_server_declared_snapshot "$dir" assets packages/manifest
  )"
  assert_eq "$initial" "$restored" 'declared snapshot mode restoration'

  ln -s input "$dir/assets/nested/link"
  if (dev_server_declared_snapshot "$dir" assets packages/manifest) \
    >"$dir/symlink-output" 2>&1; then
    fail 'declared snapshot accepted a symlink'
  fi
  assert_contains "$dir/symlink-output" \
    'declared input is a symlink: assets/nested/link' \
    'declared snapshot symlink rejection'
)

test_atomic_install_contract() (
  local dir="$fixture/atomic"
  local source="$dir/source file"
  local target="$dir/target file"
  local fake_bin="$dir/no-mutation-bin"
  local command_name
  mkdir "$dir"
  printf 'one\n' >"$source"

  atomic_install_file "$source" "$target" 0644
  assert_eq INSTALLED "$dev_server_install_status" 'new file status'
  assert_eq 'one' "$(tr -d '\n' <"$target")" 'new file bytes'
  assert_mode 0644 "$target" 'new file mode'

  mkdir "$fake_bin"
  for command_name in chmod install mkdir mktemp mv; do
    write_executable "$fake_bin/$command_name" \
      "printf 'unexpected mutation command: $command_name\\n' >&2" \
      'exit 97'
  done
  PATH="$fake_bin:$PATH" atomic_install_file "$source" "$target" 0644
  assert_eq 'UP TO DATE' "$dev_server_install_status" 'no-op file status'

  chmod 0600 "$target"
  atomic_install_file "$source" "$target" 0644
  assert_eq UPDATED "$dev_server_install_status" 'mode repair status'
  assert_mode 0644 "$target" 'repaired file mode'

  printf 'two\n' >"$source"
  atomic_install_file "$source" "$target" 0644
  assert_eq UPDATED "$dev_server_install_status" 'content update status'
  assert_eq 'two' "$(tr -d '\n' <"$target")" 'updated file bytes'

  if find "$dir" -maxdepth 1 -name '.target file.dev-server.*' -print -quit | grep -q .; then
    fail 'atomic install left a staging file'
  fi
)

test_atomic_install_rejects_invalid_nodes() (
  local dir="$fixture/atomic-invalid"
  mkdir "$dir"
  printf 'desired\n' >"$dir/source"
  printf 'preserve\n' >"$dir/referent"
  ln -s referent "$dir/target"

  if (atomic_install_file "$dir/source" "$dir/target" 0644) >"$dir/symlink-output" 2>&1; then
    fail 'atomic install accepted a target symlink'
  fi
  assert_eq preserve "$(tr -d '\n' <"$dir/referent")" 'symlink referent preservation'
  assert_contains "$dir/symlink-output" 'ERROR  managed target is a symlink' 'target symlink rejection'

  ln -s source "$dir/source-link"
  if (atomic_install_file "$dir/source-link" "$dir/new-target" 0644) >"$dir/source-output" 2>&1; then
    fail 'atomic install accepted a source symlink'
  fi
  assert_contains "$dir/source-output" 'ERROR  managed source is not a regular non-symlink file' 'source symlink rejection'

  mkdir "$dir/directory-target"
  if (atomic_install_file "$dir/source" "$dir/directory-target" 0644) >"$dir/directory-output" 2>&1; then
    fail 'atomic install accepted a directory target'
  fi
  assert_contains "$dir/directory-output" 'ERROR  managed target is not a regular file' 'directory target rejection'

  if (atomic_install_file "$dir/source" "$dir/mode-target" 7777) >"$dir/mode-output" 2>&1; then
    fail 'atomic install accepted an invalid mode'
  fi
  [[ ! -e "$dir/mode-target" ]] || fail 'invalid mode mutated the target'
)

test_atomic_install_cleans_failed_stage() (
  local dir="$fixture/atomic-failure"
  local fake_bin="$dir/bin"
  mkdir "$dir"
  mkdir "$fake_bin"
  printf 'desired\n' >"$dir/source"
  write_executable "$fake_bin/install" 'exit 23'

  if (PATH="$fake_bin:$PATH" atomic_install_file "$dir/source" "$dir/target" 0600) >"$dir/output" 2>&1; then
    fail 'atomic install ignored a staging write failure'
  fi
  [[ ! -e "$dir/target" ]] || fail 'failed atomic install created the target'
  if find "$dir" -maxdepth 1 -name '.target.dev-server.*' -print -quit | grep -q .; then
    fail 'failed atomic install left a staging file'
  fi
)

test_privileged_atomic_contract() (
  local dir="$fixture/atomic-root"
  local fake_bin="$dir/bin"
  local log_file="$dir/sudo.log"
  mkdir "$dir"
  mkdir "$fake_bin"
  printf 'root-owned-policy\n' >"$dir/source"
  write_executable "$fake_bin/sudo" \
    'printf "%s\\n" "$*" >>"$FAKE_SUDO_LOG"' \
    '[[ "${1:-}" != -- ]] || shift' \
    'exec "$@"'

  PATH="$fake_bin:$PATH" FAKE_SUDO_LOG="$log_file" \
    atomic_install_file_as_root "$dir/source" "$dir/target" 0640
  assert_eq INSTALLED "$dev_server_install_status" 'privileged install status'
  assert_mode 0640 "$dir/target" 'privileged install mode'
  assert_contains "$log_file" 'mktemp' 'privileged same-directory staging'
  assert_contains "$log_file" 'install -m 0640' 'privileged staged install'
  assert_contains "$log_file" 'mv -f' 'privileged atomic promotion'
)

test_directory_contract() (
  local dir="$fixture/directory"
  local target="$dir/owned"
  local fake_bin="$dir/no-mutation-bin"
  local command_name
  local output="$dir/output"
  mkdir "$dir"

  ensure_directory "$target" 0700 >"$output"
  assert_eq INSTALLED "$dev_server_install_status" 'directory create status'
  assert_mode 0700 "$target" 'directory create mode'
  assert_contains "$output" "INSTALLED  $target" 'directory create result'

  mkdir "$fake_bin"
  for command_name in chmod mkdir; do
    write_executable "$fake_bin/$command_name" \
      "printf 'unexpected mutation command: $command_name\\n' >&2" \
      'exit 97'
  done
  PATH="$fake_bin:$PATH" ensure_directory "$target" 0700 >"$output"
  assert_eq 'UP TO DATE' "$dev_server_install_status" 'directory no-op status'
  [[ ! -s "$output" ]] || fail 'directory no-op rendered a mutation'

  chmod 0755 "$target"
  ensure_directory "$target" 0700 >"$output"
  assert_eq UPDATED "$dev_server_install_status" 'directory repair status'
  assert_mode 0700 "$target" 'directory repaired mode'

  ln -s owned "$dir/link"
  if (ensure_directory "$dir/link" 0700) >"$output" 2>&1; then
    fail 'ensure_directory accepted a symlink'
  fi
  assert_contains "$output" 'ERROR  managed directory is a symlink' 'directory symlink rejection'
)

test_change_contract() (
  local change_id
  for change_id in \
    tmux.config shell.config desktop.session ssh.config docker.config \
    skid.unit skid.runtime skid.integration tailscale.serve system.reboot; do
    record_change "$change_id"
    has_change "$change_id" || fail "recorded change is absent: $change_id"
  done
  assert_eq 10 "$dev_server_change_count" 'closed registry size'
  record_change tmux.config
  assert_eq 10 "$dev_server_change_count" 'change deduplication'

  if (record_change package.config) >"$fixture/change-unknown" 2>&1; then
    fail 'change registry accepted an unknown identifier'
  fi
  if (record_change INVALID) >"$fixture/change-invalid" 2>&1; then
    fail 'change registry accepted malformed input'
  fi
)

test_managed_file_contract() (
  local dir="$fixture/managed"
  local output="$dir/output"
  mkdir "$dir"
  printf 'set -g mouse on\n' >"$dir/source"

  install_managed_file "$dir/source" "$dir/target" 0644 tmux.config >"$output"
  assert_eq INSTALLED "$dev_server_install_status" 'managed file install status'
  has_change tmux.config || fail 'managed file did not record its consumer'
  assert_eq 1 "$dev_server_change_count" 'managed file change count'
  assert_contains "$output" "INSTALLED  tmux.config: $dir/target" 'managed file result'

  : >"$output"
  install_managed_file "$dir/source" "$dir/target" 0644 tmux.config >"$output"
  assert_eq 'UP TO DATE' "$dev_server_install_status" 'managed file no-op status'
  assert_eq 1 "$dev_server_change_count" 'managed file no-op change count'
  [[ ! -s "$output" ]] || fail 'managed file no-op rendered a result'
)

test_result_contract() (
  local dir="$fixture/results"
  local output="$dir/output"
  local status
  mkdir "$dir"

  for status in INSTALLED UPDATED CHANGED STARTED RELOADED RESTARTED DEFERRED ACTION 'UP TO DATE' ERROR; do
    render_result "$status" fixture >>"$output"
  done
  assert_eq 3 "$dev_server_result_mutations" 'mutation result count'
  assert_eq 3 "$dev_server_result_activations" 'activation result count'
  assert_eq 1 "$dev_server_result_deferrals" 'deferral result count'
  assert_eq 1 "$dev_server_result_actions" 'action result count'
  assert_eq 1 "$dev_server_result_errors" 'error result count'

  if finish_results workstation >>"$output"; then
    fail 'error summary returned success'
  else
    assert_eq 1 "$?" 'error summary exit'
  fi
  assert_contains "$output" 'ERROR  workstation: 1 error(s), 1 action(s)' 'error summary'

  if (render_result UNKNOWN fixture) >"$dir/unknown" 2>&1; then
    fail 'result renderer accepted an unknown status'
  fi
)

test_finish_exit_contract() {
  local dir="$fixture/finish"
  mkdir "$dir"

  (
    source "$repo_dir/lib/common.sh"
    finish_results macbook >"$dir/noop"
  )
  assert_contains "$dir/noop" 'UP TO DATE  macbook' 'no-op summary'

  (
    source "$repo_dir/lib/common.sh"
    render_result DEFERRED desktop.session >"$dir/deferred"
    finish_results arch >>"$dir/deferred"
  )
  assert_contains "$dir/deferred" 'DEFERRED  arch: 1 deferral(s); durable state installed' 'deferred success summary'

  if (
    source "$repo_dir/lib/common.sh"
    render_result ACTION tailscale.serve >"$dir/action"
    finish_results devbox >>"$dir/action"
  ); then
    fail 'action summary returned success'
  else
    assert_eq 2 "$?" 'action summary exit'
  fi
  assert_contains "$dir/action" 'ACTION  devbox: 1 user action(s) required' 'action summary'
}

main() {
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-helpers.XXXXXX")"
  trap cleanup EXIT HUP INT TERM

  run_test test_sha_contract
  run_test test_declared_snapshot_contract
  run_test test_atomic_install_contract
  run_test test_atomic_install_rejects_invalid_nodes
  run_test test_atomic_install_cleans_failed_stage
  run_test test_privileged_atomic_contract
  run_test test_directory_contract
  run_test test_change_contract
  run_test test_managed_file_contract
  run_test test_result_contract
  run_test test_finish_exit_contract

  printf 'helpers: %d contract groups passed\n' "$tests_run"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
