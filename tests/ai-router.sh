#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
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

test_portable_sha256() {
  local empty="$fixture/empty"
  local expected_digest=e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  : >"$empty"
  assert_eq "$expected_digest" \
    "$(PATH=/usr/bin:/bin dev_server_sha256 "$empty")" \
    'native platform SHA-256 command'
  (
    command() {
      [[ "${1:-}" == -v && "${2:-}" =~ ^(sha256sum|shasum)$ ]] || builtin command "$@"
    }
    sha256sum() {
      assert_eq 2 "$#" 'sha256sum argv count'
      assert_eq -- "$1" 'sha256sum option terminator'
      assert_eq "$empty" "$2" 'sha256sum path'
      printf '%s  fixture\n' "$expected_digest"
    }
    shasum() { fail 'shasum ran while sha256sum was available'; }
    assert_eq "$expected_digest" "$(dev_server_sha256 "$empty")" 'sha256sum preference'
  )
  (
    command() {
      if [[ "${1:-}" == -v && "${2:-}" == sha256sum ]]; then return 1; fi
      if [[ "${1:-}" == -v && "${2:-}" == shasum ]]; then return 0; fi
      builtin command "$@"
    }
    shasum() {
      assert_eq 4 "$#" 'shasum argv count'
      assert_eq -a "$1" 'shasum algorithm option'
      assert_eq 256 "$2" 'shasum algorithm'
      assert_eq -- "$3" 'shasum option terminator'
      assert_eq "$empty" "$4" 'shasum path'
      printf '%s  fixture\n' "$expected_digest"
    }
    assert_eq "$expected_digest" "$(dev_server_sha256 "$empty")" 'shasum fallback'
  )
  if (
    command() { [[ "${1:-}" != -v ]] && builtin command "$@"; }
    dev_server_sha256 "$empty"
  ) >/dev/null 2>&1; then
    fail 'SHA-256 helper accepted a host with no supported digest command'
  fi
  pass
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
  pass
}

test_codex_platform_pin_mapping() {
  dev_server_home() { printf '%s\n' "$test_home"; }
  die() { fail "$*"; }
  # shellcheck source=lib/ai-tools.sh
  source "$repo_dir/lib/ai-tools.sh"

  local platform_system
  local platform_machine
  uname() {
    case "${1:-}" in
      -s) printf '%s\n' "$platform_system" ;;
      -m) printf '%s\n' "$platform_machine" ;;
      *) return 64 ;;
    esac
  }

  local row expected_path expected_digest
  for row in \
    'Linux x86_64 codex-linux-x64/vendor/x86_64-unknown-linux-musl/bin/codex 73dc5888888f411c1f0fa7b81d866e721dcc86b527ce8e3b2cf4708661e823ba' \
    'Darwin arm64 codex-darwin-arm64/vendor/aarch64-apple-darwin/bin/codex f0d8762236594359b60cfbe17f4c7e945a3ce8d1c91e74778838c968d250fb6c'; do
    read -r platform_system platform_machine expected_path expected_digest <<<"$row"
    expected_path="$test_home/.local/lib/node_modules/@openai/codex/node_modules/@openai/$expected_path"
    assert_eq "$expected_path" "$(ai_codex_platform_binary)" \
      "$platform_system $platform_machine Codex payload path"
    assert_eq "$expected_digest" "$(ai_codex_platform_sha256)" \
      "$platform_system $platform_machine Codex payload digest"
  done

  platform_system=Darwin
  platform_machine=x86_64
  if (ai_codex_platform_binary >/dev/null 2>&1); then
    fail 'unsupported Codex host architecture received a platform pin'
  fi
  if (ai_codex_platform_sha256 >/dev/null 2>&1); then
    fail 'unsupported Codex host architecture received a platform digest'
  fi
  unset -f uname
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
  fixture_platform_digest="$(dev_server_sha256 "$fixture_platform_binary")"
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

test_portable_sha256
test_hard_cut_surface
test_codex_platform_pin_mapping
test_explicit_contexts_and_exact_argv
test_bare_context_inference
test_pin_doctor_and_convergence

printf 'PASS: %d ai-router test groups\n' "$tests_run"
