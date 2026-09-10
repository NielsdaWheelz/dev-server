#!/usr/bin/env bash
# Globals in this fixture are consumed by sourced production functions.
# shellcheck disable=SC2034
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-ai-profile.XXXXXX")"
fixture="$(cd "$fixture" && pwd -P)"
trap 'rm -rf "$fixture"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  tests_run=$((tests_run + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$actual" == "$expected" ]] ||
    fail "$label: expected [$expected], got [$actual]"
}

test_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

file_inode() {
  stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

reset_results() {
  dev_server_changes='|'
  dev_server_change_count=0
  dev_server_result_mutations=0
  dev_server_result_activations=0
  dev_server_result_deferrals=0
  dev_server_result_actions=0
  dev_server_result_errors=0
  dev_server_install_status='UP TO DATE'
}

test_home="$fixture/home"
test_assets="$fixture/assets"
record="$fixture/record"
stdout_file="$fixture/stdout"
stderr_file="$fixture/stderr"
npm_calls_file="$fixture/npm-calls"
npm_prefix_file="$fixture/npm-prefix"
npm_candidate=0.154.0
npm_install_status=0
claude_bootstrap_record="$fixture/claude-bootstrap"
claude_install_record="$fixture/claude-install"
claude_next_version_file="$fixture/claude-next-version"
status=0
tests_run=0
fields=()

install -d -m 0755 "$test_home"
cp -R "$repo_dir/assets" "$test_assets"
printf '%s\n' /unexpected >"$npm_prefix_file"
dev_server_home_dir="$test_home"
dev_server_assets_root="$test_assets"
export CLAUDE_INSTALL_RECORD="$claude_install_record"
export CLAUDE_NEXT_VERSION_FILE="$claude_next_version_file"
# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=lib/ai-tools.sh
source "$repo_dir/lib/ai-tools.sh"

read_record() {
  local field

  [[ -s "$record" ]] || fail 'missing AI command record'
  fields=()
  while IFS= read -r -d '' field; do
    fields+=("$field")
  done <"$record"
}

assert_argv() {
  local label="$1"
  shift
  local -a expected=("$@")
  local index

  assert_eq "${#expected[@]}" "$((${#fields[@]} - 5))" "$label argv count"
  for index in "${!expected[@]}"; do
    assert_eq "${expected[$index]}" "${fields[$((index + 5))]}" \
      "$label argv $index"
  done
}

write_fake_codex() {
  local target="$1"

  install -d -m 0755 "$(dirname "$target")"
  # These variables belong to the generated fake.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ "${1:-}" == --version ]]; then' \
    "  printf 'codex-cli $npm_candidate\\n'" \
    '  exit 0' \
    'fi' \
    '{' \
    '  printf '\''%s\0%s\0%s\0%s\0%s\0'\'' "${0##*/}" "${CODEX_HOME:-}" "${CLAUDE_CONFIG_DIR:-}" "$PWD" "${PROFILE_SENTINEL:-}"' \
    '  printf '\''%s\0'\'' "$@"' \
    "} >'$record'" >"$target"
  chmod 0755 "$target"
}

write_fake_claude_version() {
  local target="$test_home/.local/share/claude/versions/$1"
  local version="$1"

  install -d -m 0755 "$(dirname "$target")"
  # These variables belong to the generated fake.
  # shellcheck disable=SC2016
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    "version='$version'" \
    'case "${1:-}" in' \
    '  --version) printf "%s (Claude Code)\n" "$version"; exit 0 ;;' \
    '  install)' \
    '    [[ "${2:-}" == latest ]]' \
    '    printf "install-latest\n" >>"$CLAUDE_INSTALL_RECORD"' \
    '    if [[ -s "$CLAUDE_NEXT_VERSION_FILE" ]]; then' \
    '      next="$(cat "$CLAUDE_NEXT_VERSION_FILE")"' \
    '      ln -sfn "$HOME/.local/share/claude/versions/$next" "$HOME/.local/bin/claude"' \
    '      : >"$CLAUDE_NEXT_VERSION_FILE"' \
    '    fi' \
    '    exit 0' \
    '    ;;' \
    'esac' \
    '[[ -n "${PROFILE_RECORD:-}" ]] || exit 1' \
    '{' \
    '  printf '\''%s\0%s\0%s\0%s\0%s\0'\'' "${0##*/}" "${CODEX_HOME:-}" "${CLAUDE_CONFIG_DIR:-}" "$PWD" "${PROFILE_SENTINEL:-}"' \
    '  printf '\''%s\0'\'' "$@"' \
    '} >"$PROFILE_RECORD"' >"$target"
  chmod 0755 "$target"
}

install_fake_native_claude() {
  local version="$1"

  write_fake_claude_version "$version"
  install -d -m 0755 "$test_home/.local/bin"
  ln -s "$test_home/.local/share/claude/versions/$version" \
    "$test_home/.local/bin/claude"
}

ai_bootstrap_claude_native() {
  printf 'bootstrap\n' >>"$claude_bootstrap_record"
  install_fake_native_claude 2.1.257
}

npm_operation_count() {
  local operation="$1"

  if [[ -f "$npm_calls_file" ]]; then
    grep -Fxc "$operation" "$npm_calls_file" || true
  else
    printf '0\n'
  fi
}

npm() {
  local prefix

  if [[ "${1:-}" == --version ]]; then
    printf '11.19.0\n'
    return 0
  fi
  case "${1:-}:${2:-}" in
  config:get)
    assert_eq 3 "$#" 'npm config-get argument count'
    assert_eq prefix "$3" 'npm config-get key'
    cat "$npm_prefix_file"
    ;;
  config:set)
    assert_eq 5 "$#" 'npm config-set argument count'
    assert_eq --location=user "$3" 'npm config-set location'
    assert_eq prefix "$4" 'npm config-set key'
    printf '%s\n' "$5" >"$npm_prefix_file"
    printf 'config-set\n' >>"$npm_calls_file"
    ;;
  view:@openai/codex)
    assert_eq 3 "$#" 'npm candidate argument count'
    assert_eq dist-tags.latest "$3" 'upstream stable channel'
    printf 'view\n' >>"$npm_calls_file"
    printf '%s\n' "$npm_candidate"
    ;;
  install:--global)
    assert_eq 8 "$#" 'npm global-install argument count'
    assert_eq --prefix "$3" 'npm global prefix flag'
    assert_eq --ignore-scripts "$5" 'Codex install-script policy'
    assert_eq --no-audit "$6" 'npm global audit policy'
    assert_eq --no-fund "$7" 'npm global funding policy'
    assert_eq "@openai/codex@$npm_candidate" "$8" 'resolved stable package'
    ((npm_install_status == 0)) || return "$npm_install_status"
    prefix="$4"
    printf 'global-install\n' >>"$npm_calls_file"
    install -d -m 0755 "$prefix/lib/node_modules/@openai/codex" "$prefix/bin"
    printf '{"name":"@openai/codex","version":"%s"}\n' "$npm_candidate" \
      >"$prefix/lib/node_modules/@openai/codex/package.json"
    write_fake_codex "$prefix/bin/codex"
    ;;
  *) fail "unexpected npm invocation: $*" ;;
  esac
}

test_runtime_floor() {
  ai_require_codex_runtime
  if (
    npm() { printf '11.16.9\n'; }
    ai_require_codex_runtime
  ) >/dev/null 2>&1; then
    fail 'Codex runtime accepted an unsupported npm version'
  fi
  pass
}

test_invalid_input_is_read_only() {
  local invalid_assets="$fixture/invalid-assets"
  local invalid_home="$fixture/invalid-home"

  cp -R "$repo_dir/assets" "$invalid_assets"
  rm "$invalid_assets/routers/ai-profile"
  ln -s "$fixture/untrusted" "$invalid_assets/routers/ai-profile"
  install -d -m 0755 "$invalid_home"
  if (
    dev_server_home_dir="$invalid_home"
    dev_server_assets_root="$invalid_assets"
    ai_install
  ) >/dev/null 2>&1; then
    fail 'AI apply accepted a symlinked profile declaration'
  fi
  assert_eq 0 "$(find "$invalid_home" -mindepth 1 | wc -l | tr -d ' ')" \
    'invalid AI input mutation count'
  pass
}

test_canonical_install_and_update() {
  local profile_inode

  dev_server_ai_host=arch

  reset_results
  ai_install_dirs >/dev/null
  ai_install_packages >/dev/null
  ai_install_profiles >/dev/null
  has_change shell.config || fail 'fresh profile install did not report shell.config'

  assert_eq 1 "$(npm_operation_count view)" 'fresh Codex candidate resolution count'
  assert_eq 1 "$(npm_operation_count global-install)" 'fresh Codex install count'
  assert_eq 1 "$(npm_operation_count config-set)" 'npm prefix repair count'
  assert_eq 1 "$(wc -l <"$claude_bootstrap_record" | tr -d ' ')" \
    'fresh Claude bootstrap count'
  assert_eq "$test_home/.local" "$(cat "$npm_prefix_file")" \
    'canonical npm prefix'
  [[ -x "$test_home/.local/bin/codex" ]] || fail 'canonical Codex is missing'
  assert_eq 2.1.257 "$(ai_claude_native_version)" 'native Claude version'
  for command in codex codex-work codex-work2 claude-work; do
    [[ -f "$test_home/bin/$command" && ! -L "$test_home/bin/$command" ]] ||
      fail "$command is not a regular managed wrapper"
    assert_eq 755 "$(test_mode "$test_home/bin/$command")" "$command mode"
  done
  [[ ! -e "$test_home/bin/claude" ]] || fail 'plain Claude was replaced'

  profile_inode="$(file_inode "$test_home/bin/codex-work")"
  reset_results
  ai_install_dirs >/dev/null
  ai_install_packages >/dev/null
  ai_install_profiles >/dev/null
  assert_eq 2 "$(npm_operation_count view)" 'second Codex candidate resolution count'
  assert_eq 1 "$(npm_operation_count global-install)" 'second Codex install count'
  assert_eq 1 "$(wc -l <"$claude_install_record" | tr -d ' ')" \
    'second-apply Claude latest reconciliation count'
  assert_eq "$profile_inode" "$(file_inode "$test_home/bin/codex-work")" \
    'second-apply profile inode'
  ((dev_server_result_mutations == 0)) ||
    fail 'second AI apply reported a durable mutation'

  npm_candidate=0.155.0
  ai_install_packages >/dev/null
  assert_eq 2 "$(npm_operation_count global-install)" \
    'new stable Codex update count'
  assert_eq "$npm_candidate" "$(ai_package_version "$(ai_codex_manifest)" @openai/codex)" \
    'installed latest stable version'

  write_fake_claude_version 2.1.258
  printf '2.1.258\n' >"$claude_next_version_file"
  reset_results
  ai_install_claude >/dev/null
  assert_eq 2.1.258 "$(ai_claude_native_version)" 'updated native Claude version'
  assert_eq 1 "$dev_server_result_mutations" 'Claude update mutation count'
  pass
}

invoke() {
  local command="$1"
  local cwd="$2"
  shift 2

  rm -f "$record" "$stdout_file" "$stderr_file"
  set +e
  (
    cd "$cwd"
    env -u CODEX_HOME -u CLAUDE_CONFIG_DIR \
      HOME="$test_home" \
      PATH="$test_home/.local/bin:$test_home/bin:/usr/bin:/bin" \
      PROFILE_RECORD="$record" \
      PROFILE_SENTINEL='preserved value' \
      "$command" "$@"
  ) >"$stdout_file" 2>"$stderr_file"
  status=$?
  set -e
}

test_claude_profile_routing() {
  local personal_cwd="$fixture/personal-project"
  local work_cwd="$fixture/work-project"

  install -d -m 0755 "$personal_cwd" "$work_cwd"

  invoke claude-work "$personal_cwd" -C "$work_cwd" --exact
  assert_eq 0 "$status" 'claude-work status'
  read_record
  assert_eq "$test_home/.local/bin/claude" \
    "$(command -v "$test_home/.local/bin/claude")" 'Claude binary path'
  assert_eq "$test_home/.claude-work" "${fields[2]}" \
    'claude-work CLAUDE_CONFIG_DIR'
  assert_argv claude-work -C "$work_cwd" --exact

  invoke claude "$work_cwd" --session-id example
  assert_eq 0 "$status" 'plain Claude status'
  read_record
  assert_eq '' "${fields[2]}" 'plain Claude CLAUDE_CONFIG_DIR'
  pass
}

test_installed_codex_profiles_forward_native_arguments() (
  local command profile
  export HOME="$test_home"
  dev_server_ai_host=arch
  ai_install_profiles >/dev/null
  for command in codex codex-work codex-work2; do
    case "$command" in
    codex) profile=personal ;;
    codex-work) profile=work ;;
    codex-work2) profile=work2 ;;
    esac
    invoke "$test_home/bin/$command" "$fixture" resume 11111111-1111-1111-1111-111111111111 --model 'model value'
    assert_eq 0 "$status" "$command native resume status"
    read_record
    assert_argv "$command" resume 11111111-1111-1111-1111-111111111111 --model 'model value'
    assert_eq "$fixture" "${fields[3]}" "$command caller cwd"
    assert_eq 'preserved value' "${fields[4]}" "$command caller environment"
    if [[ "$profile" == personal ]]; then
      assert_eq "$test_home/.codex" "${fields[1]}" "$command account home"
    else
      assert_eq "$test_home/.codex-$profile" "${fields[1]}" "$command account home"
    fi
  done
)

test_all_hosts_shared_profiles_are_quiescent() (
  local first_inode host command expected_launcher="$fixture/expected-launcher"
  export HOME="$test_home"
  for host in devbox macbook arch; do
    dev_server_ai_host="$host"
    reset_results
    ai_install_profiles >/dev/null
    ai_codex_host launcher >"$expected_launcher"
    for command in codex codex-work codex-work2; do
      [[ -f "$test_home/bin/$command" && ! -L "$test_home/bin/$command" ]] ||
        fail "$host $command is not a managed shared launcher"
      cmp -s "$expected_launcher" "$test_home/bin/$command" ||
        fail "$host $command does not route to the shared service"
    done
    cmp -s "$test_assets/routers/ai-profile" "$test_home/bin/claude-work" ||
      fail "$host changed the Claude launcher"
    first_inode="$(file_inode "$test_home/bin/codex-work")"
    reset_results
    ai_install_profiles >/dev/null
    assert_eq "$first_inode" "$(file_inode "$test_home/bin/codex-work")" \
      "$host second-apply launcher inode"
    assert_eq 0 "$dev_server_result_mutations" "$host second-apply mutations"
  done
)

test_existing_account_permissions_are_preserved() (
  local account
  for account in .codex .codex-work .codex-work2; do
    chmod 0750 "$test_home/$account"
  done
  ai_install_dirs >/dev/null
  for account in .codex .codex-work .codex-work2; do
    assert_eq 750 "$(test_mode "$test_home/$account")" "$account existing mode"
  done
)

test_all_hosts_preserve_native_install_failure_and_reject_unstable_candidate() (
  local host candidate before
  before="$(ai_package_version "$(ai_codex_manifest)" @openai/codex)"
  for host in devbox macbook arch; do
    dev_server_ai_host="$host"
    npm_install_status=1
    for candidate in 0.156.0 0.156.0-beta.1; do
      npm_candidate="$candidate"
      if [[ "$candidate" == *-* ]]; then
        npm_install_status=0
      fi
      if (ai_install_codex) >"$stdout_file" 2>"$stderr_file"; then
        fail "$host accepted failed native installation or an unstable candidate"
      fi
      assert_eq "$before" "$(ai_package_version "$(ai_codex_manifest)" @openai/codex)" \
        "$host existing package after failure"
      [[ ! -s "$stdout_file" ]] || fail "$host reported installation after failure"
    done
  done
)

test_fail_closed() {
  local unsupported="$test_home/bin/codex-personal"

  install -m 0755 "$test_assets/routers/ai-profile" "$unsupported"
  invoke "$unsupported" "$fixture" --version
  assert_eq 64 "$status" 'unsupported profile basename status'

  rm "$test_home/bin/codex-work"
  ln -s "$fixture/unmanaged" "$test_home/bin/codex-work"
  if (ai_install_profiles) >/dev/null 2>&1; then
    fail 'profile installation accepted a symlink target'
  fi
  assert_eq 0 "$(find "$test_home/bin" -name '.codex-profile.*' | wc -l | tr -d ' ')" \
    'launcher candidates after failed installation'

  rm "$test_home/.local/bin/claude"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$test_home/.local/bin/claude"
  chmod 0755 "$test_home/.local/bin/claude"
  if (ai_install_claude) >/dev/null 2>&1; then
    fail 'Claude apply accepted a non-native canonical command'
  fi
  pass
}

test_runtime_floor
test_invalid_input_is_read_only
test_canonical_install_and_update
test_claude_profile_routing
test_installed_codex_profiles_forward_native_arguments
pass
test_all_hosts_shared_profiles_are_quiescent
pass
test_existing_account_permissions_are_preserved
pass
test_all_hosts_preserve_native_install_failure_and_reject_unstable_candidate
pass
test_fail_closed

printf 'PASS: %d AI profile test groups\n' "$tests_run"
