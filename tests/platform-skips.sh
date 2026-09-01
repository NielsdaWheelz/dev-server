#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-workstation.XXXXXX")"
test_repo="$fixture/repo"
fake_bin="$fixture/bin"
stage_tmp="$fixture/tmp"
record="$fixture/record"
stdout_file="$fixture/stdout"
stderr_file="$fixture/stderr"
status=0
tests_run=0
trap 'rm -rf -- "$fixture"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$actual" == "$expected" ]] ||
    fail "$label: expected [$expected], got [$actual]"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

pass() {
  tests_run=$((tests_run + 1))
}

write_library() {
  local path="$1"
  shift
  printf '%s\n' '#!/usr/bin/env bash' "$@" >"$path"
}

install -d -m 0755 \
  "$test_repo/lib" \
  "$test_repo/assets" \
  "$test_repo/packages" \
  "$fake_bin" \
  "$stage_tmp"
install -m 0755 "$repo_dir/workstation" "$test_repo/workstation"
install -m 0644 "$repo_dir/lib/common.sh" "$test_repo/lib/common.sh"
printf 'source-v1\n' >"$test_repo/assets/staged-input"
printf 'fixture brew manifest\n' >"$test_repo/packages/Brewfile"
chmod 0755 "$test_repo/assets/staged-input"
chmod 0644 "$test_repo/packages/Brewfile"
write_library "$test_repo/lib/packages-macos.sh" \
  'packages_validate_inputs() { :; }' \
  'packages_install() {' \
  '  if [[ "${WORKSTATION_MUTATE_SOURCE:-0}" == 1 ]]; then' \
  '    printf "source-v2\n" >"$WORKSTATION_SOURCE/assets/staged-input"' \
  '    chmod 0600 "$WORKSTATION_SOURCE/assets/staged-input"' \
  '  fi' \
  '  if [[ "${WORKSTATION_INSPECT_STAGE:-0}" == 1 ]]; then' \
  '    printf "stage-package-mode %s\n" "$(file_mode "$dev_server_root/packages/Brewfile")" >>"$WORKSTATION_RECORD"' \
  '  fi' \
  '  printf "packages\n" >>"$WORKSTATION_RECORD"' \
  '  record_change system.reboot' \
  '}'
write_library "$test_repo/lib/packages-arch.sh" \
  'packages_validate_inputs() { :; }' \
  'packages_install() { printf "packages-arch\n" >>"$WORKSTATION_RECORD"; }'
write_library "$test_repo/lib/dotfiles.sh" \
  'dotfiles_validate_declared_inputs() { :; }' \
  'dotfiles_validate_local_state() { :; }' \
  'dotfiles_install() {' \
  '  if [[ "${WORKSTATION_INSPECT_STAGE:-0}" == 1 ]]; then' \
  '    printf "stage-asset %s\n" "$(tr -d "\\n" <"$(dev_server_assets_dir)/staged-input")" >>"$WORKSTATION_RECORD"' \
  '    printf "stage-asset-mode %s\n" "$(file_mode "$(dev_server_assets_dir)/staged-input")" >>"$WORKSTATION_RECORD"' \
  '    printf "stage-root %s\n" "$dev_server_root" >>"$WORKSTATION_RECORD"' \
  '  fi' \
  '  printf "dotfiles\n" >>"$WORKSTATION_RECORD"' \
  '  record_change desktop.session' \
  '}'
write_library "$test_repo/lib/personal-arch.sh" \
  'personal_arch_owned_host() { return 1; }' \
  'personal_arch_validate_declared_inputs() { :; }' \
  'personal_arch_apply() { printf "personal-arch\n" >>"$WORKSTATION_RECORD"; }'
write_library "$test_repo/lib/skidbladnir.sh" \
  'skidbladnir_validate_declared_inputs() { :; }' \
  'skidbladnir_validate_local_state() { :; }' \
  'skidbladnir_preflight_existing_serve() { return 0; }' \
  'skidbladnir_apply() { printf "skidbladnir %s\n" "$1" >>"$WORKSTATION_RECORD"; }'
write_library "$test_repo/lib/ai-tools.sh" \
  'ai_validate_inputs() { [[ "${FAIL_LATE_INPUT:-0}" != 1 ]] || die "invalid late AI input"; }' \
  'ai_install() { printf "ai\n" >>"$WORKSTATION_RECORD"; }'
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "${FAKE_UNAME:?}"' >"$fake_bin/uname"
chmod 0755 "$fake_bin/uname"

invoke() {
  : >"$record"
  : >"$stdout_file"
  : >"$stderr_file"
  set +e
  (
    umask "${WORKSTATION_TEST_UMASK:-022}"
    PATH="$fake_bin:$PATH" \
      TMPDIR="$stage_tmp" \
      FAKE_UNAME="${FAKE_UNAME:-Darwin}" \
      WORKSTATION_RECORD="$record" \
      WORKSTATION_SOURCE="$test_repo" \
      "$test_repo/workstation" "$@" >"$stdout_file" 2>"$stderr_file"
  )
  status=$?
  set -e
}

assert_stage_cleaned() {
  ! find "$stage_tmp" -mindepth 1 -maxdepth 1 \
    -name 'workstation-declared.*' -print -quit | grep -q . ||
    fail 'workstation left a declared-input stage'
}

test_explicit_api() {
  invoke
  assert_eq 64 "$status" 'omitted operation status'
  assert_contains "$stderr_file" 'Usage: ./workstation apply'
  [[ ! -s "$record" ]] || fail 'omitted operation mutated state'

  invoke help
  assert_eq 0 "$status" 'help status'
  assert_contains "$stdout_file" 'Usage: ./workstation apply'
  [[ ! -s "$record" ]] || fail 'help mutated state'

  invoke --help extra
  assert_eq 64 "$status" 'help with extra argument status'
  [[ ! -s "$record" ]] || fail 'invalid help mutated state'

  invoke unknown
  assert_eq 64 "$status" 'unknown operation status'
  [[ ! -s "$record" ]] || fail 'unknown operation mutated state'
  pass
}

test_macos_order_and_deferrals() {
  FAKE_UNAME=Darwin invoke apply
  assert_eq 0 "$status" 'macOS apply status'
  assert_eq $'packages\ndotfiles\nai\nskidbladnir macos' \
    "$(<"$record")" 'macOS subsystem order'
  assert_eq 1 "$(grep -c '^DEFERRED  desktop session:' "$stdout_file")" \
    'desktop-session deferral count'
  assert_eq 1 "$(grep -c '^DEFERRED  reboot:' "$stdout_file")" \
    'reboot deferral count'
  assert_contains "$stdout_file" \
    'DEFERRED  macbook: 2 deferral(s); durable state installed'
  pass
}

test_platform_gate_is_read_only() {
  FAKE_UNAME=FreeBSD invoke apply
  assert_eq 1 "$status" 'unsupported platform status'
  [[ ! -s "$record" ]] || fail 'unsupported platform mutated state'
  assert_contains "$stderr_file" \
    'ERROR  unsupported workstation platform: FreeBSD'

  FAKE_UNAME=Linux invoke apply
  assert_eq 1 "$status" 'unowned Linux status'
  [[ ! -s "$record" ]] || fail 'unowned Linux mutated state'
  assert_contains "$stderr_file" \
    'ERROR  workstation apply supports only the owned arch host'
  pass
}

test_late_input_preflight_is_read_only() {
  FAIL_LATE_INPUT=1 FAKE_UNAME=Darwin invoke apply
  assert_eq 1 "$status" 'late invalid input status'
  [[ ! -s "$record" ]] || fail 'late invalid input reached package mutation'
  assert_contains "$stderr_file" 'ERROR  invalid late AI input'
  pass
}

test_immutable_declared_stage() {
  printf 'source-v1\n' >"$test_repo/assets/staged-input"
  chmod 0755 "$test_repo/assets/staged-input"

  WORKSTATION_INSPECT_STAGE=1 \
    WORKSTATION_MUTATE_SOURCE=1 \
    FAKE_UNAME=Darwin invoke apply
  assert_eq 0 "$status" 'input-race apply status'
  assert_contains "$record" 'stage-asset source-v1'
  assert_contains "$record" 'stage-asset-mode 755'
  assert_eq source-v2 "$(tr -d '\n' <"$test_repo/assets/staged-input")" \
    'source mutation fixture'
  assert_eq 600 "$(
    stat -c '%a' "$test_repo/assets/staged-input" 2>/dev/null ||
      stat -f '%Lp' "$test_repo/assets/staged-input"
  )" 'source mode mutation fixture'
  if grep -Fq "stage-root $test_repo" "$record"; then
    fail 'workstation subsystems read the mutable source tree'
  fi
  assert_stage_cleaned
  pass
}

test_restrictive_umask_preserves_stage_modes() {
  printf 'source-v1\n' >"$test_repo/assets/staged-input"
  chmod 0755 "$test_repo/assets/staged-input"
  chmod 0644 "$test_repo/packages/Brewfile"

  WORKSTATION_INSPECT_STAGE=1 \
    WORKSTATION_TEST_UMASK=077 \
    FAKE_UNAME=Darwin invoke apply
  assert_eq 0 "$status" 'restrictive-umask apply status'
  assert_contains "$record" 'stage-package-mode 644'
  assert_contains "$record" 'stage-asset-mode 755'
  assert_stage_cleaned
  pass
}

test_static_hard_cut() {
  if grep -Eq '(doctor|converge|repair|force|minimal|full)' \
    "$repo_dir/workstation"; then
    fail 'legacy command or mode remains in workstation'
  fi
  assert_contains "$repo_dir/workstation" \
    'skidbladnir_apply "$workstation_platform"'
  assert_contains "$repo_dir/workstation" \
    'finish_results "$workstation_target"'
  pass
}

test_explicit_api
test_macos_order_and_deferrals
test_platform_gate_is_read_only
test_late_input_preflight_is_read_only
test_immutable_declared_stage
test_restrictive_umask_preserves_stage_modes
test_static_hard_cut

printf 'PASS: %d workstation API groups\n' "$tests_run"
