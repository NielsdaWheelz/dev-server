#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-ai-router.XXXXXX")"
test_home="$fixture/home"
router="$test_home/.local/libexec/ai-router"
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
  if [[ "$status" != "$1" ]]; then
    fail "$2 status: got <$status>, want <$1>; stderr: $(tr '\n' ' ' <"$stderr_file")"
  fi
}

read_record() {
  local field
  [[ -s "$record" ]] || fail 'missing routed process record'
  fields=()
  while IFS= read -r -d '' field; do
    fields+=("$field")
  done <"$record"
}

assert_argv() {
  local label="$1"
  shift
  local -a expected=("$@")
  assert_eq "${#expected[@]}" "$((${#fields[@]} - 4))" "$label argv count"
  local index
  for index in "${!expected[@]}"; do
    assert_eq "${expected[$index]}" "${fields[$((index + 4))]}" "$label argv $index"
  done
}

pass() {
  tests_run=$((tests_run + 1))
}

install -d -m 0755 "$test_home/.local/libexec" "$test_home/.local/bin" "$test_home/bin"
install -d -m 0700 \
  "$test_home/.codex-personal" "$test_home/.codex-work" "$test_home/.codex-work2" \
  "$test_home/.claude-personal" "$test_home/.claude-work"
sed "s|/home/niels|$test_home|g" "$repo_dir/assets/routers/ai-router" >"$router"
chmod 0755 "$router"
for command in codex codex-personal codex-work codex-work2 claude claude-personal claude-work; do
  ln -s "$router" "$test_home/bin/$command"
done

for tool in codex claude; do
  cat >"$test_home/.local/bin/$tool" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
{
  printf '%s\0%s\0%s\0%s\0' "$(basename "$0")" "${CODEX_HOME:-}" "${CLAUDE_CONFIG_DIR:-}" "${ROUTER_SENTINEL:-}"
  printf '%s\0' "$@"
} >"$ROUTER_RECORD"
if [[ "${1:-}" == --version && $# -eq 1 ]]; then
  printf '%s\n' "${FAKE_TOOL_VERSION:-codex-cli 0.149.1}"
fi
EOF
  chmod 0755 "$test_home/.local/bin/$tool"
done

invoke() {
  local command="$1"
  local tmux_state="$2"
  shift 2
  rm -f -- "$record" "$stdout_file" "$stderr_file"
  local -a environment=(
    "HOME=$test_home"
    "PATH=$test_home/bin:/usr/bin:/bin"
    "ROUTER_RECORD=$record"
    'ROUTER_SENTINEL=preserved value'
  )
  set +e
  if [[ "$tmux_state" == inside ]]; then
    env -u CODEX_HOME -u CLAUDE_CONFIG_DIR "${environment[@]}" \
      TMUX="$fixture/tmux,1,0" TMUX_PANE=%7 \
      "$test_home/bin/$command" "$@" >"$stdout_file" 2>"$stderr_file"
  else
    env -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u TMUX -u TMUX_PANE "${environment[@]}" \
      "$test_home/bin/$command" "$@" >"$stdout_file" 2>"$stderr_file"
  fi
  status=$?
  set -e
}

test_hard_cut_surface() {
  local source="$repo_dir/assets/routers/ai-router"
  ! grep -Eq 'skidbladnir|router-seam|TMUX|launcher|status-hook' "$source" ||
    fail 'retired Skidbladnir interception remains in the account router'
  grep -Fxq "  printf '73dc5888888f411c1f0fa7b81d866e721dcc86b527ce8e3b2cf4708661e823ba\\n'" \
    "$repo_dir/lib/ai-tools.sh" || fail 'missing frozen Codex platform digest'
  pass
}

test_explicit_contexts_and_exact_argv() {
  local row command variable want
  for row in \
    'codex-personal CODEX /home/.codex-personal' \
    'codex-work CODEX /home/.codex-work' \
    'codex-work2 CODEX /home/.codex-work2' \
    'claude-personal CLAUDE /home/.claude-personal' \
    'claude-work CLAUDE /home/.claude-work'; do
    read -r command variable want <<<"$row"
    want="${want/\/home/$test_home}"
    invoke "$command" inside --flag 'spaced value' '' -- resume
    assert_status 0 "$command inside tmux"
    read_record
    assert_eq 'preserved value' "${fields[3]}" "$command environment"
    if [[ "$variable" == CODEX ]]; then
      assert_eq "$want" "${fields[1]}" "$command CODEX_HOME"
      assert_eq '' "${fields[2]}" "$command CLAUDE_CONFIG_DIR"
    else
      assert_eq '' "${fields[1]}" "$command CODEX_HOME"
      assert_eq "$want" "${fields[2]}" "$command CLAUDE_CONFIG_DIR"
    fi
    assert_argv "$command" --flag 'spaced value' '' -- resume
  done
  pass
}

test_bare_context_inference() {
  install -d -m 0755 "$test_home/src/personal/project" "$test_home/src/work/project"
  invoke codex outside -C "$test_home/src/work/project" exec --exact
  assert_status 0 'bare Codex work path'
  read_record
  assert_eq "$test_home/.codex-work" "${fields[1]}" 'bare Codex work CODEX_HOME'

  invoke codex outside "--cd=$test_home/src/personal/project" exec --exact
  assert_status 0 'bare Codex personal path'
  read_record
  assert_eq "$test_home/.codex-personal" "${fields[1]}" 'bare Codex personal CODEX_HOME'

  invoke claude inside -C "$test_home/src/work/project" --exact
  assert_status 0 'bare Claude work path inside tmux'
  read_record
  assert_eq "$test_home/.claude-work" "${fields[2]}" 'bare Claude work CLAUDE_CONFIG_DIR'
  pass
}

test_pin_doctor_and_convergence() {
  dev_server_home() { printf '%s\n' "$test_home"; }
  dev_server_assets_dir() { printf '%s/assets\n' "$repo_dir"; }
  die() { fail "$*"; }
  doctor_result=''
  doctor_pass() { doctor_result=pass; }
  doctor_warn() { doctor_result=warn; }
  doctor_fail() { doctor_result=fail; }
  # shellcheck source=lib/ai-tools.sh
  source "$repo_dir/lib/ai-tools.sh"

  local fixture_platform_binary="$fixture/codex-platform"
  local fixture_platform_digest
  printf 'reviewed fake platform binary\n' >"$fixture_platform_binary"
  chmod 0755 "$fixture_platform_binary"
  fixture_platform_digest="$(shasum -a 256 "$fixture_platform_binary" | awk '{print $1}')"
  ai_codex_platform_binary() { printf '%s\n' "$fixture_platform_binary"; }
  ai_codex_platform_sha256() { printf '%s\n' "$fixture_platform_digest"; }

  assert_eq '@openai/codex@0.149.1' "$(ai_tool_package codex)" 'Codex npm pin'
  ai_install_router
  ai_install_router
  cmp -s "$repo_dir/assets/routers/ai-router" "$test_home/.local/libexec/ai-router" ||
    fail 'router convergence differs from the repo asset'

  local original_home="$HOME"
  export HOME="$test_home"
  export ROUTER_RECORD="$record"
  export FAKE_TOOL_VERSION='codex-cli 0.149.1'
  ai_doctor_tool codex
  assert_eq pass "$doctor_result" 'exact Codex doctor'
  printf 'drift\n' >>"$fixture_platform_binary"
  doctor_result=''
  ai_doctor_tool codex
  assert_eq fail "$doctor_result" 'wrong Codex platform digest doctor'
  unset FAKE_TOOL_VERSION ROUTER_RECORD
  export HOME="$original_home"
  pass
}

test_hard_cut_surface
test_explicit_contexts_and_exact_argv
test_bare_context_inference
test_pin_doctor_and_convergence

printf 'PASS: %d ai-router test groups\n' "$tests_run"
