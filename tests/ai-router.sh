#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
token='Skidbladnir.Router.V1'
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-ai-router.XXXXXX")"
test_home="$fixture/home"
test_bin="$fixture/bin"
router="$test_home/.local/libexec/ai-router"
marker_dir="$test_home/.local/state/skidbladnir/router"
marker="$marker_dir/enabled"
launcher="$test_home/.local/bin/skidbladnir"
record="$fixture/record"
stdout_file="$fixture/stdout"
stderr_file="$fixture/stderr"
status=0
tests_run=0

cleanup() {
  rm -rf -- "$fixture"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local want="$1"
  local got="$2"
  local label="$3"
  [[ "$got" == "$want" ]] || fail "$label: got <$got>, want <$want>"
}

assert_status() {
  assert_eq "$1" "$status" "$2 status"
}

assert_empty() {
  [[ ! -s "$1" ]] || fail "$2 must be empty"
}

assert_record_kind() {
  local want="$1"
  [[ -s "$record" ]] || fail "missing $want boundary record"
  mapfile -d '' -t fields < "$record"
  assert_eq "$want" "${fields[0]}" "boundary kind"
}

assert_no_record() {
  [[ ! -e "$record" ]] || fail "failed route reached a binary boundary"
}

assert_record_argv() {
  local label="$1"
  shift
  local -a expected=("$@")
  assert_eq "${#expected[@]}" "$(( ${#fields[@]} - 4 ))" "$label argv count"
  local index
  for index in "${!expected[@]}"; do
    assert_eq "${expected[$index]}" "${fields[$((index + 4))]}" "$label argv $index"
  done
}

pass() {
  tests_run=$((tests_run + 1))
}

mkdir -p "$test_home/.local/libexec" "$test_home/.local/bin" "$test_home/bin" \
  "$test_home/.codex-personal" "$test_home/.codex-work" "$test_home/.codex-work2" \
  "$test_home/.claude-personal" "$test_home/.claude-work" "$test_bin"
chmod 0700 "$test_home/.codex-personal" "$test_home/.codex-work" "$test_home/.codex-work2" \
  "$test_home/.claude-personal" "$test_home/.claude-work"

# The production seam paths are deliberately absolute. Substitute only in the
# isolated copy while separately asserting the production literals below.
sed "s|/home/niels|$test_home|g" "$repo_dir/assets/routers/ai-router" > "$router"
chmod 0755 "$router"
for command in codex codex-personal codex-work codex-work2; do
  ln -s "$router" "$test_home/bin/$command"
done

cat > "$test_home/.local/bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'real\0%s\0%s\0%s\0' "${CODEX_HOME:-}" "$PWD" "${ROUTER_SENTINEL:-}"
  printf '%s\0' "$@"
} > "$ROUTER_RECORD"
if [[ "${1:-}" == "--version" && $# -eq 1 ]]; then
  printf '%s\n' "${FAKE_CODEX_VERSION:-codex-cli 0.149.1}"
fi
EOF
chmod 0755 "$test_home/.local/bin/codex"

cat > "$launcher" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $# -eq 2 && "$1" == launcher && "$2" == --router-seam-version ]]; then
  case "${FAKE_LAUNCHER_QUERY:-ok}" in
    ok) printf 'Skidbladnir.Router.V1\n' ;;
    mismatch) printf 'Skidbladnir.Router.V0\n' ;;
    framing) printf 'Skidbladnir.Router.V1\n\n' ;;
    stderr) printf 'Skidbladnir.Router.V1\n'; printf 'unexpected\n' >&2 ;;
    fail) exit 9 ;;
    hang) sleep 30 ;;
  esac
  exit 0
fi
{
  printf 'launcher\0%s\0%s\0%s\0' "${CODEX_HOME:-}" "$PWD" "${ROUTER_SENTINEL:-}"
  printf '%s\0' "$@"
} > "$ROUTER_RECORD"
EOF
chmod 0755 "$launcher"

cat > "$test_bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "${FAKE_TMUX_VALID:-1}" == 1 ]] || exit 1
[[ $# -eq 5 && "$1" == display-message && "$2" == -p && "$3" == -t && "$4" == "${TMUX_PANE:-}" && "$5" == '#{pane_id}|#{pane_tty}' ]] || exit 2
printf '%s|%s\n' "${FAKE_TMUX_RESULT:-${TMUX_PANE:-}}" "${FAKE_PANE_TTY:-/dev/pts/7}"
EOF
chmod 0755 "$test_bin/tmux"

cat > "$test_bin/tty" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${FAKE_CALLER_TTY:-/dev/pts/7}"
EOF
chmod 0755 "$test_bin/tty"

cat > "$test_bin/stat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${FAKE_MARKER_DIR_UID:-}" != "" && $# -eq 3 && "$1" == -c && "$2" == %u && "$3" == */.local/state/skidbladnir/router ]]; then
  printf '%s\n' "$FAKE_MARKER_DIR_UID"
  exit 0
fi
if [[ "${FAKE_MARKER_UID:-}" != "" && $# -eq 3 && "$1" == -c && "$2" == %u && "$3" == */.local/state/skidbladnir/router/enabled ]]; then
  printf '%s\n' "$FAKE_MARKER_UID"
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod 0755 "$test_bin/stat"

enable_marker() {
  install -d -m 0700 "$marker_dir"
  rm -f -- "$marker"
  printf '%s\n' "$token" > "$marker"
  chmod 0600 "$marker"
}

disable_marker() {
  rm -rf -- "$marker_dir"
}

invoke() {
  local command="$1"
  local tmux_state="$2"
  shift 2
  rm -f -- "$record" "$stdout_file" "$stderr_file"
  local -a environment=(
    "HOME=$test_home"
    "PATH=$test_bin:/usr/bin:/bin"
    "ROUTER_RECORD=$record"
    'ROUTER_SENTINEL=preserved value'
    "FAKE_LAUNCHER_QUERY=${FAKE_LAUNCHER_QUERY:-ok}"
    "FAKE_MARKER_DIR_UID=${FAKE_MARKER_DIR_UID:-}"
    "FAKE_MARKER_UID=${FAKE_MARKER_UID:-}"
    "FAKE_TMUX_VALID=${FAKE_TMUX_VALID:-1}"
    "FAKE_TMUX_RESULT=${FAKE_TMUX_RESULT:-}"
    "FAKE_PANE_TTY=${FAKE_PANE_TTY:-/dev/pts/7}"
    "FAKE_CALLER_TTY=${FAKE_CALLER_TTY:-/dev/pts/7}"
  )
  set +e
  if [[ "$tmux_state" == inside ]]; then
    env "${environment[@]}" TMUX="$fixture/tmux,1,0" TMUX_PANE=%7 \
      "$test_home/bin/$command" "$@" > "$stdout_file" 2> "$stderr_file"
  else
    env -u TMUX -u TMUX_PANE "${environment[@]}" \
      "$test_home/bin/$command" "$@" > "$stdout_file" 2> "$stderr_file"
  fi
  status=$?
  set -e
}

assert_production_literals() {
  grep -Fxq "skidbladnir_seam_token='Skidbladnir.Router.V1'" "$repo_dir/assets/routers/ai-router" || fail 'missing frozen seam token'
  grep -Fxq "skidbladnir_marker='/home/niels/.local/state/skidbladnir/router/enabled'" "$repo_dir/assets/routers/ai-router" || fail 'missing frozen marker path'
  grep -Fxq "skidbladnir_launcher='/home/niels/.local/bin/skidbladnir'" "$repo_dir/assets/routers/ai-router" || fail 'missing frozen launcher path'
  grep -Fxq "  printf '73dc5888888f411c1f0fa7b81d866e721dcc86b527ce8e3b2cf4708661e823ba\\n'" "$repo_dir/lib/ai-tools.sh" || fail 'missing frozen Codex platform digest'
  pass
}

test_query() {
  "$router" --skidbladnir-seam-version > "$stdout_file" 2> "$stderr_file" || fail 'router seam query failed'
  printf '%s\n' "$token" > "$fixture/expected"
  cmp -s "$fixture/expected" "$stdout_file" || fail 'router seam query stdout mismatch'
  assert_empty "$stderr_file" 'router seam query stderr'
  pass
}

test_marker_absent() {
  disable_marker
  local command home row
  for row in 'codex-personal .codex-personal' 'codex-work .codex-work' 'codex-work2 .codex-work2'; do
    read -r command home <<< "$row"
    invoke "$command" inside --strict-config 'ordinary prompt'
    assert_status 0 "$command marker-absent root"
    assert_record_kind real
    assert_eq "$test_home/$home" "${fields[1]}" "$command marker-absent CODEX_HOME"
  done
  invoke codex-personal inside resume 123e4567-e89b-42d3-a456-426614174000
  assert_status 0 'marker-absent resume'
  assert_record_kind real
  pass
}

test_enabled_profiles_and_argv() {
  enable_marker
  local command profile home row
  local -a expected
  for row in 'codex-personal personal .codex-personal' 'codex-work work .codex-work' 'codex-work2 work2 .codex-work2'; do
    read -r command profile home <<< "$row"
    invoke "$command" inside --strict-config -C "$repo_dir" -m 'model value' 'prompt with spaces' ''
    assert_status 0 "$command managed root"
    assert_record_kind launcher
    assert_eq "$test_home/$home" "${fields[1]}" "$command CODEX_HOME"
    assert_eq 'preserved value' "${fields[3]}" "$command environment"
    expected=(launcher --profile "$profile" -- --strict-config -C "$repo_dir" -m 'model value' 'prompt with spaces' '')
    assert_record_argv "$command" "${expected[@]}"
  done
  invoke codex-personal inside
  assert_status 0 'zero-argv managed root'
  assert_record_kind launcher
  assert_record_argv 'zero-argv managed root' launcher --profile personal --
  pass
}

test_grammar() {
  enable_marker
  local -a argv
  local -a managed_cases=(
    'resume'
    '--strict-config resume 123e4567-e89b-42d3-a456-426614174000'
    '--image=image.png resume 123e4567-e89b-42d3-a456-426614174000'
    '-iimage.png resume 123e4567-e89b-42d3-a456-426614174000'
    '-i=image.png resume 123e4567-e89b-42d3-a456-426614174000'
    'prefix resume 123e4567-e89b-42d3-a456-426614174000'
    '-- resume'
    '-m resume'
    '-i image.png resume'
    '--image image.png exec'
    '-i image.png --strict-config resume 123e4567-e89b-42d3-a456-426614174000'
    '--not-in-this-pin resume'
    '--not-in-this-pin exec'
  )
  local spec
  for spec in "${managed_cases[@]}"; do
    read -r -a argv <<< "$spec"
    invoke codex-personal inside "${argv[@]}"
    assert_status 0 "managed grammar: $spec"
    assert_record_kind launcher
  done

  local -a direct_cases=(
    '--help'
    '--version'
    'resume --help'
    'exec --fake'
    'e --fake'
    '--image=image.png exec --fake'
    '-iimage.png exec --fake'
    '-i=image.png exec --fake'
    '--strict-config exec --fake'
    'review --fake'
    'login status'
    'logout --fake'
    'agents --fake'
    'app-server --fake'
    'remote-control --fake'
    'mcp --fake'
    'plugin --fake'
    'mcp-server --fake'
    'completion bash'
    'update --fake'
    'doctor --fake'
    'sandbox --fake'
    'debug --fake'
    'apply --fake'
    'a --fake'
    'queue --fake'
    'archive --fake'
    'delete --fake'
    'migrate-rollouts --fake'
    'unarchive --fake'
    'fork --fake'
    'cloud --fake'
    'exec-server --fake'
    'execpolicy --help'
    'cloud-tasks --help'
    'responses-api-proxy --help'
    'stdio-to-uds --help'
    'features --fake'
    'help --fake'
  )
  for spec in "${direct_cases[@]}"; do
    read -r -a argv <<< "$spec"
    invoke codex-personal inside "${argv[@]}"
    assert_status 0 "direct grammar: $spec"
    assert_record_kind real
  done

  invoke codex-work2 inside exec --flag 'spaced value' '' -- resume
  assert_status 0 'direct exact argv'
  assert_record_kind real
  assert_eq "$test_home/.codex-work2" "${fields[1]}" 'direct exact CODEX_HOME'
  assert_eq 'preserved value' "${fields[3]}" 'direct exact environment'
  assert_record_argv 'direct exact' exec --flag 'spaced value' '' -- resume
  pass
}

test_outside_and_stale_tmux() {
  enable_marker
  invoke codex-work outside resume 123e4567-e89b-42d3-a456-426614174000
  assert_status 0 'outside tmux resume'
  assert_record_kind real

  invoke codex-work outside 'root prompt'
  assert_status 0 'outside tmux root'
  assert_record_kind real

  mkdir -p "$test_home/src/work/project" "$test_home/src/personal/project"
  invoke codex outside -C "$test_home/src/work/project" exec --fake
  assert_status 0 'bare codex work inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex work CODEX_HOME'
  invoke codex outside -C "$test_home/src/personal/project" exec --fake
  assert_status 0 'bare codex personal inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-personal" "${fields[1]}" 'bare codex personal CODEX_HOME'

  invoke codex outside "-C$test_home/src/work/project" exec --fake
  assert_status 0 'bare codex attached-short work inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex attached-short work CODEX_HOME'
  invoke codex outside "-C=$test_home/src/work/project" exec --fake
  assert_status 0 'bare codex equals-short work inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex equals-short work CODEX_HOME'
  invoke codex outside "--cd=$test_home/src/work/project" exec --fake
  assert_status 0 'bare codex attached-long work inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex attached-long work CODEX_HOME'
  invoke codex outside --cd "$test_home/src/work/project" exec --fake
  assert_status 0 'bare codex separate-long work inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex separate-long work CODEX_HOME'

  invoke codex outside ordinary-prompt "--cd=$test_home/src/work/project"
  assert_status 0 'bare codex post-prompt flag inference'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex post-prompt flag CODEX_HOME'

  invoke codex outside -C "$test_home/src/personal/project" resume \
    "-C$test_home/src/work/project"
  assert_status 0 'bare codex resume-scoped cwd precedence'
  assert_record_kind real
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare codex resume-scoped cwd CODEX_HOME'
  invoke codex outside -C "$test_home/src/work/project" resume \
    "--cd=$test_home/src/personal/project"
  assert_status 0 'bare codex resume-scoped personal cwd precedence'
  assert_record_kind real
  assert_eq "$test_home/.codex-personal" "${fields[1]}" 'bare codex resume-scoped personal cwd CODEX_HOME'

  invoke codex outside -- "--cd=$test_home/src/work/project"
  assert_status 0 'bare codex end-of-options prompt'
  assert_record_kind real
  assert_eq "$test_home/.codex-personal" "${fields[1]}" 'bare codex end-of-options prompt CODEX_HOME'

  FAKE_TMUX_VALID=0 invoke codex-work inside 'root prompt'
  assert_status 0 'stale tmux root'
  assert_record_kind real
  unset FAKE_TMUX_VALID

  FAKE_CALLER_TTY=/dev/pts/8 invoke codex-work inside 'root prompt'
  assert_status 0 'foreign tmux pane tty'
  assert_record_kind real
  unset FAKE_CALLER_TTY
  pass
}

assert_managed_failure() {
  invoke codex-personal inside 'root prompt'
  [[ "$status" -ne 0 ]] || fail "$1 must fail"
  assert_no_record
  [[ -s "$stderr_file" ]] || fail "$1 must fail visibly"
}

test_marker_failures() {
  enable_marker
  chmod 0644 "$marker"
  assert_managed_failure 'marker mode'

  enable_marker
  chmod 0755 "$marker_dir"
  assert_managed_failure 'marker directory mode'

  enable_marker
  printf 'Skidbladnir.Router.V0\n' > "$marker"
  assert_managed_failure 'marker content'

  enable_marker
  printf '%s\n\n' "$token" > "$marker"
  assert_managed_failure 'marker framing'

  enable_marker
  FAKE_MARKER_UID=99999 assert_managed_failure 'marker uid'
  unset FAKE_MARKER_UID

  enable_marker
  FAKE_MARKER_DIR_UID=99999 assert_managed_failure 'marker directory uid'
  unset FAKE_MARKER_DIR_UID

  enable_marker
  mv "$marker" "$fixture/marker-target"
  ln -s "$fixture/marker-target" "$marker"
  assert_managed_failure 'marker symlink'

  # Invalid marker state is irrelevant to an outside-tmux or other command.
  invoke codex-personal outside 'root prompt'
  assert_status 0 'outside malformed marker'
  assert_record_kind real
  invoke codex-personal inside exec --fake
  assert_status 0 'other command malformed marker'
  assert_record_kind real
  pass
}

test_launcher_failures() {
  enable_marker
  mv "$launcher" "$fixture/launcher-saved"
  assert_managed_failure 'launcher absent'
  mv "$fixture/launcher-saved" "$launcher"

  chmod 0644 "$launcher"
  assert_managed_failure 'launcher not executable'
  chmod 0755 "$launcher"

  local mode
  for mode in mismatch framing stderr fail; do
    FAKE_LAUNCHER_QUERY="$mode" assert_managed_failure "launcher query $mode"
  done
  FAKE_LAUNCHER_QUERY=hang assert_managed_failure 'launcher query hang'
  unset FAKE_LAUNCHER_QUERY
  pass
}

test_pin_doctor_and_convergence() {
  # Source only function definitions; this library has no top-level mutation.
  dev_server_home() { printf '%s\n' "$test_home"; }
  dev_server_assets_dir() { printf '%s/assets\n' "$repo_dir"; }
  die() { fail "$*"; }
  doctor_pass() { doctor_result=pass; }
  doctor_warn() { doctor_result=warn; }
  doctor_fail() { doctor_result=fail; }
  # shellcheck disable=SC1091
  source "$repo_dir/lib/ai-tools.sh"

  local fixture_platform_binary="$fixture/codex-platform"
  local fixture_platform_digest
  printf 'reviewed fake platform binary\n' > "$fixture_platform_binary"
  chmod 0755 "$fixture_platform_binary"
  fixture_platform_digest="$(sha256sum "$fixture_platform_binary" | awk '{print $1}')"
  ai_codex_platform_binary() { printf '%s\n' "$fixture_platform_binary"; }
  ai_codex_platform_sha256() { printf '%s\n' "$fixture_platform_digest"; }

  assert_eq '@openai/codex@0.149.1' "$(ai_tool_package codex)" 'Codex npm pin'

  disable_marker
  ai_install_router
  [[ ! -e "$marker" && ! -L "$marker" ]] || fail 'router convergence enabled absent marker'

  enable_marker
  cp "$marker" "$fixture/marker-before"
  ai_install_router
  ai_install_router
  cmp -s "$fixture/marker-before" "$marker" || fail 'router convergence changed marker'
  assert_eq 600 "$(stat -c %a "$marker")" 'converged marker mode'

  local original_home="$HOME"
  export HOME="$test_home"
  export ROUTER_RECORD="$record"
  doctor_result=''
  export FAKE_CODEX_VERSION='codex-cli 0.149.1'
  ai_doctor_tool codex
  assert_eq pass "$doctor_result" 'exact Codex doctor'
  printf 'drift\n' >> "$fixture_platform_binary"
  doctor_result=''
  ai_doctor_tool codex
  assert_eq fail "$doctor_result" 'wrong Codex platform digest doctor'
  printf 'reviewed fake platform binary\n' > "$fixture_platform_binary"
  doctor_result=''
  export FAKE_CODEX_VERSION='codex-cli 0.149.2'
  ai_doctor_tool codex
  assert_eq fail "$doctor_result" 'wrong Codex doctor'
  unset FAKE_CODEX_VERSION
  unset ROUTER_RECORD
  export HOME="$original_home"
  pass
}

assert_production_literals
test_query
test_marker_absent
test_enabled_profiles_and_argv
test_grammar
test_outside_and_stale_tmux
test_marker_failures
test_launcher_failures
test_pin_doctor_and_convergence

printf 'PASS: %d ai-router test groups\n' "$tests_run"
