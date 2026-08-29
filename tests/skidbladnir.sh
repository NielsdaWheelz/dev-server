#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-skidbladnir-test.XXXXXX")"
test_home="$fixture/home"
test_bin="$fixture/bin"
tests_run=0
test_socket_dir=""

cleanup() {
  rm -rf -- "$fixture"
  [[ -z "$test_socket_dir" ]] || rm -rf -- "$test_socket_dir"
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

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_exact_line_once() {
  local file="$1"
  local line="$2"
  [[ "$(grep -Fxc -- "$line" "$file" || true)" == 1 ]] ||
    fail "$file must contain exactly once: $line"
}

deployment_owned_snapshot() {
  local target
  for target in "$@"; do
    [[ -f "$target" && ! -L "$target" ]] ||
      fail "deployment-owned snapshot target is not a regular file: $target"
    printf '%s %s\n' \
      "$(skidbladnir_file_mode "$target")" \
      "$(skidbladnir_sha256 "$target")"
  done
}

plist_json() {
  local file="$1"
  if [[ "$(uname -s)" == Darwin ]]; then
    /usr/bin/plutil -convert json -o - "$file"
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import json, plistlib, sys; json.dump(plistlib.load(open(sys.argv[1], "rb")), sys.stdout)' "$file"
  else
    fail 'a plist parser (macOS plutil or Python 3) is required'
  fi
}

assert_no_secret() {
  local file="$1"
  local secret
  for secret in "$arch_token" "$devbox_token" "$local_token" "$bearer"; do
    [[ -z "$secret" ]] || ! grep -Fq "$secret" "$file" || fail "$file contains a fleet secret"
  done
}

pass() {
  tests_run=$((tests_run + 1))
}

test_macos_tmux_tracks_homebrew_stable() {
  local package_fixture="$fixture/macos-packages"
  local package_root="$package_fixture/repo"
  local package_bin="$package_fixture/bin"
  local package_calls="$package_fixture/calls"
  local package_pinned="$package_fixture/pinned"
  local package_tmux_template="$package_fixture/tmux-template"
  local package_tmux_version="$package_fixture/tmux-version"
  local expected_calls="$package_fixture/expected-calls"
  install -d -m 0755 "$package_root/packages" "$package_bin"
  printf 'brew "tmux"\n' >"$package_root/packages/Brewfile"
  cat >"$package_tmux_template" <<'EOF'
#!/usr/bin/env bash
printf 'tmux %s\n' "$(cat "$BREW_TEST_TMUX_VERSION")"
EOF
  cat >"$package_bin/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  unpin)
    [[ "${2:-}" == --formula && "${3:-}" == tmux ]]
    printf 'unpin --formula tmux\n' >>"$BREW_TEST_CALLS"
    rm -f -- "$BREW_TEST_PINNED"
    ;;
  update)
    printf 'update\n' >>"$BREW_TEST_CALLS"
    ;;
  bundle)
    printf 'bundle\n' >>"$BREW_TEST_CALLS"
    [[ ! -f "$BREW_TEST_PINNED" ]]
    cp "$BREW_TEST_TMUX_TEMPLATE" "$BREW_TEST_TMUX_PATH"
    chmod 0755 "$BREW_TEST_TMUX_PATH"
    printf '%s\n' "$BREW_TEST_BUNDLE_VERSION" >"$BREW_TEST_TMUX_VERSION"
    ;;
  list)
    [[ "${2:-}" == --pinned && "${3:-}" == --formula ]]
    printf 'list --pinned --formula\n' >>"$BREW_TEST_CALLS"
    if [[ -f "$BREW_TEST_PINNED" ]]; then
      printf 'tmux\n'
    fi
    ;;
  *)
    exit 64
    ;;
esac
EOF
  chmod 0755 "$package_tmux_template" "$package_bin/brew"

  run_packages_install() {
    (
      export PATH="$package_bin:/usr/bin:/bin"
      export BREW_TEST_CALLS="$package_calls"
      export BREW_TEST_PINNED="$package_pinned"
      export BREW_TEST_TMUX_TEMPLATE="$package_tmux_template"
      export BREW_TEST_TMUX_PATH="$package_bin/tmux"
      export BREW_TEST_TMUX_VERSION="$package_tmux_version"
      export BREW_TEST_BUNDLE_VERSION="$1"
      dev_server_root="$package_root"
      require_cmd() { command -v "$1" >/dev/null 2>&1; }
      # shellcheck source=lib/packages-macos.sh
      source "$repo_dir/lib/packages-macos.sh"
      packages_macos_configure_tailscale() { :; }
      packages_install
    )
  }

  cp "$package_tmux_template" "$package_bin/tmux"
  chmod 0755 "$package_bin/tmux"
  printf '3.7c\n' >"$package_tmux_version"
  : >"$package_pinned"
  run_packages_install 3.7d
  printf '%s\n' \
    'list --pinned --formula' \
    'unpin --formula tmux' \
    update \
    bundle \
    >"$expected_calls"
  cmp -s "$expected_calls" "$package_calls" ||
    fail 'macOS convergence did not unpin tmux before refreshing Homebrew'
  assert_eq 'tmux 3.7d' "$(BREW_TEST_TMUX_VERSION="$package_tmux_version" "$package_bin/tmux" -V)" \
    'macOS convergence did not install the current stable tmux release'
  [[ ! -e "$package_pinned" ]] || fail 'macOS convergence left tmux pinned'

  rm -f -- "$package_bin/tmux" "$package_tmux_version" "$package_pinned" "$package_calls"
  run_packages_install 3.8
  printf '%s\n' 'list --pinned --formula' update bundle >"$expected_calls"
  cmp -s "$expected_calls" "$package_calls" ||
    fail 'fresh macOS convergence did not refresh Homebrew before installation'
  assert_eq 'tmux 3.8' "$(BREW_TEST_TMUX_VERSION="$package_tmux_version" "$package_bin/tmux" -V)" \
    'fresh macOS convergence did not install the current stable tmux release'
  ! grep -Eq 'packages_macos_(pin|doctor_tmux_pin)|package[.]tmux-pin|brew pin' \
    "$repo_dir/lib/packages-macos.sh" || fail 'retired macOS tmux pinning remains'
  pass
}

test_assets_and_operator_copy() {
  local pin="$repo_dir/assets/skidbladnir/release-pin.json"
  local workstation_skid_line workstation_ai_line devbox_skid_line devbox_ai_line
  assert_exact_line_once "$repo_dir/skidbladnir" 'source "$base_dir/lib/doctor.sh"'
  assert_exact_line_once "$repo_dir/skidbladnir" 'source "$base_dir/lib/packages-macos.sh"'
  jq -e '
    type == "object" and keys == ["androidApkSha256", "androidSigningCertAssetSha256", "darwinArm64Sha256", "linuxAmd64Sha256", "sha256SumsAssetSha256", "sourceSha", "version"] and
    (([.[]] | all(. == "PENDING")) or
      ((.version | test("^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) and
       (.sourceSha | test("^[0-9a-f]{40}$")) and
       (.androidApkSha256 | test("^[0-9a-f]{64}$")) and
       (.androidSigningCertAssetSha256 | test("^[0-9a-f]{64}$")) and
       (.linuxAmd64Sha256 | test("^[0-9a-f]{64}$")) and
       (.darwinArm64Sha256 | test("^[0-9a-f]{64}$")) and
       (.sha256SumsAssetSha256 | test("^[0-9a-f]{64}$"))))
  ' "$pin" >/dev/null || fail 'release pin must be wholly pending or wholly canonical'
  cmp -s "$pin" <(jq -S . "$pin") || fail 'release pin keys are not stored in sorted order'
  jq -e '
    if ([.[]] | all(. == "PENDING")) then true
    else
      (.version | capture("^v(?<major>0|[1-9][0-9]*)\\.(?<minor>0|[1-9][0-9]*)\\.(?<patch>0|[1-9][0-9]*)$") |
        ((.major | tonumber) * 1000000) +
        ((.minor | tonumber) * 1000) +
        (.patch | tonumber)) >= 2010
    end
  ' "$pin" >/dev/null || fail 'pre-agent-identity Skidbladnir release remains active'

  workstation_skid_line="$(grep -nF '  skidbladnir_converge "$(platform_id)"' \
    "$repo_dir/workstation" | cut -d: -f1)"
  workstation_ai_line="$(grep -nF '  ai_install' "$repo_dir/workstation" | cut -d: -f1)"
  [[ -n "$workstation_skid_line" && -n "$workstation_ai_line" &&
    "$workstation_skid_line" -lt "$workstation_ai_line" ]] ||
    fail 'workstation activates the AI router before the Claude plugin owner converges'
  devbox_skid_line="$(grep -nF '    - role: skidbladnir' \
    "$repo_dir/ansible/playbooks/converge.yml" | cut -d: -f1)"
  devbox_ai_line="$(grep -nF '    - role: ai_tools' \
    "$repo_dir/ansible/playbooks/converge.yml" | cut -d: -f1)"
  [[ -n "$devbox_skid_line" && -n "$devbox_ai_line" &&
    "$devbox_skid_line" -lt "$devbox_ai_line" ]] ||
    fail 'devbox activates the AI router before the Claude plugin owner converges'

  local row config platform tmux_path tmux_tested_version home hooks
  for row in \
    'devbox Linux /usr/bin/tmux tmux_3.4 /home/niels agent-hooks-devbox.json' \
    'arch Linux /usr/bin/tmux tmux_3.7c /home/nnandal agent-hooks-arch.json' \
    'macbook Darwin /opt/homebrew/bin/tmux tmux_3.7c /Users/nnandal agent-hooks-macbook.json'; do
    read -r config platform tmux_path tmux_tested_version home hooks <<<"$row"
    config="$repo_dir/assets/skidbladnir/host-config-$config.json"
    tmux_tested_version="${tmux_tested_version/_/ }"
    jq -e --arg platform "$platform" --arg tmux_path "$tmux_path" \
      --arg tmux_tested_version "$tmux_tested_version" --arg home "$home" '
      type == "object" and keys == ["platform", "profiles", "tmux"] and
      .platform == $platform and .tmux == {path: $tmux_path, testedVersion: $tmux_tested_version} and
      .profiles == [
        {key:"personal",label:"Codex · Personal",provider:"Codex",command:($home + "/bin/codex-personal"),environment:[{name:"CODEX_HOME",value:($home + "/.codex-personal")}],foregroundSignatures:[{executableBase:"codex"},{executableBase:"node",argument1:($home + "/.local/bin/codex")}],arguments:["--dangerously-bypass-approvals-and-sandbox"]},
        {key:"work",label:"Codex · Work",provider:"Codex",command:($home + "/bin/codex-work"),environment:[{name:"CODEX_HOME",value:($home + "/.codex-work")}],foregroundSignatures:[{executableBase:"codex"},{executableBase:"node",argument1:($home + "/.local/bin/codex")}],arguments:["--dangerously-bypass-approvals-and-sandbox"]},
        {key:"work2",label:"Codex · Work 2",provider:"Codex",command:($home + "/bin/codex-work2"),environment:[{name:"CODEX_HOME",value:($home + "/.codex-work2")}],foregroundSignatures:[{executableBase:"codex"},{executableBase:"node",argument1:($home + "/.local/bin/codex")}],arguments:["--dangerously-bypass-approvals-and-sandbox"]},
        {key:"claude-personal",label:"Claude · Personal",provider:"Claude",command:($home + "/bin/claude-personal"),environment:[{name:"CLAUDE_CONFIG_DIR",value:($home + "/.claude-personal")}],foregroundSignatures:[{argument0:($home + "/.local/bin/claude")}],arguments:["--permission-mode","auto"]},
        {key:"claude-work",label:"Claude · Work",provider:"Claude",command:($home + "/bin/claude-work"),environment:[{name:"CLAUDE_CONFIG_DIR",value:($home + "/.claude-work")}],foregroundSignatures:[{argument0:($home + "/.local/bin/claude")}],arguments:["--permission-mode","auto"]}
      ]
    ' "$config" >/dev/null || fail "strict host config differs: $config"
    hooks="$repo_dir/assets/skidbladnir/$hooks"
    jq -e --arg home "$home" '
      type == "object" and keys == ["description", "hooks"] and
      .description == "Skíðblaðnir agent identity projection" and
      (.hooks | keys == ["SessionStart", "Stop", "UserPromptSubmit"]) and
      .hooks.SessionStart == [{
        matcher:"^(startup|resume|clear)$",
        hooks:[{type:"command",command:($home + "/.local/bin/skidbladnir agent-hook --host-config=" + $home + "/.config/skidbladnir/host-config.json Codex SessionStart"),timeout:5,async:false}]
      }] and
      .hooks.UserPromptSubmit == [{
        hooks:[{type:"command",command:($home + "/.local/bin/skidbladnir agent-hook --host-config=" + $home + "/.config/skidbladnir/host-config.json Codex UserPromptSubmit"),timeout:5,async:false}]
      }] and
      .hooks.Stop == [{
        hooks:[{type:"command",command:($home + "/.local/bin/skidbladnir agent-hook --host-config=" + $home + "/.config/skidbladnir/host-config.json Codex Stop"),timeout:5,async:false}]
      }]
    ' "$hooks" >/dev/null || fail "strict lifecycle hooks differ: $hooks"
  done

  local plugin="$repo_dir/assets/skidbladnir/claude-agent-identity"
  jq -e '
    type == "object" and keys == ["description", "name"] and
    .name == "skidbladnir-agent-identity" and
    .description == "Skíðblaðnir Claude agent identity projection"
  ' "$plugin/.claude-plugin/plugin.json" >/dev/null ||
    fail 'strict Claude plugin manifest differs'
  jq -e '
    type == "object" and keys == ["description", "hooks"] and
    .description == "Skíðblaðnir agent identity projection" and
    .hooks == {
      SessionStart: [{
        hooks: [{
          type: "command",
          command: "${CLAUDE_PLUGIN_ROOT}/bin/agent-hook",
          args: [],
          timeout: 5,
          async: false
        }]
      }]
    }
  ' "$plugin/hooks/hooks.json" >/dev/null || fail 'strict Claude plugin hooks differ'
  [[ -f "$plugin/bin/agent-hook" && ! -L "$plugin/bin/agent-hook" &&
    -x "$plugin/bin/agent-hook" ]] || fail 'Claude plugin forwarder must be executable'
  cmp -s "$plugin/bin/agent-hook" <(printf '%s\n' \
    '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '' \
    'exec "$HOME/.local/bin/skidbladnir" agent-hook \' \
    '  "--host-config=$HOME/.config/skidbladnir/host-config.json" Claude SessionStart') ||
    fail 'Claude plugin forwarder is not the closed content-free command'
  [[ -z "$(find "$repo_dir/assets/skidbladnir" -maxdepth 1 -name 'status-hooks-*' -print -quit)" ]] ||
    fail 'retired status-hook assets remain'
  ! grep -Fq 'skidbladnir_status_hooks_source' "$repo_dir/lib/skidbladnir.sh" ||
    fail 'retired status-hook deployment function remains'

  local unit="$repo_dir/assets/skidbladnir/skidbladnir.service"
  local expected_unit="$fixture/skidbladnir.service.expected"
  printf '%s\n' \
    '[Unit]' \
    'Description=Skidbladnir tmux gateway' \
    '' \
    '[Service]' \
    'Type=simple' \
    'Environment="PATH=%h/bin:%h/.local/bin:%h/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' \
    'UnsetEnvironment=TMUX TMUX_PANE TMUX_TMPDIR' \
    'ExecStart=%h/.local/bin/skidbladnir-launch gateway --listen=127.0.0.1:7341 --bearer-file=%h/.config/skidbladnir/bearer --catalogue-path=%h/.local/share/skidbladnir/characters.json --machine-handle-file=%h/.config/skidbladnir/machine-handle --host-config=%h/.config/skidbladnir/host-config.json' \
    'Restart=on-failure' \
    'RestartSec=2s' \
    'TimeoutStopSec=10s' \
    'KillMode=process' \
    'UMask=0022' \
    '' \
    '[Install]' \
    'WantedBy=default.target' \
    >"$expected_unit"
  cmp -s "$expected_unit" "$unit" ||
    fail 'systemd user service differs from the closed host boundary'

  plist_json "$repo_dir/assets/skidbladnir/dev.niels.skidbladnir.plist" |
    jq -e '
      keys == ["AbandonProcessGroup","EnvironmentVariables","ExitTimeOut","KeepAlive","Label","ProgramArguments","RunAtLoad","StandardErrorPath","StandardOutPath","ThrottleInterval","Umask","WorkingDirectory"] and
      .Label == "dev.niels.skidbladnir" and
      .ProgramArguments == [
        "/Users/nnandal/.local/bin/skidbladnir-launch", "gateway",
        "--listen=127.0.0.1:7341",
        "--bearer-file=/Users/nnandal/.config/skidbladnir/bearer",
        "--catalogue-path=/Users/nnandal/.local/share/skidbladnir/characters.json",
        "--machine-handle-file=/Users/nnandal/.config/skidbladnir/machine-handle",
        "--host-config=/Users/nnandal/.config/skidbladnir/host-config.json"
      ] and
      .EnvironmentVariables == {PATH:"/Users/nnandal/bin:/Users/nnandal/.local/bin:/Users/nnandal/.local/share/mise/shims:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"} and
      .WorkingDirectory == "/Users/nnandal" and .RunAtLoad == true and
      .KeepAlive == {SuccessfulExit:false} and .AbandonProcessGroup == true and
      .ThrottleInterval == 2 and .ExitTimeOut == 10 and .Umask == 18 and
      .StandardOutPath == "/Users/nnandal/.local/state/skidbladnir/gateway.log" and
      .StandardErrorPath == "/Users/nnandal/.local/state/skidbladnir/gateway.error.log"
    ' >/dev/null || fail 'LaunchAgent definition differs from the closed host boundary'
  [[ -x "$repo_dir/assets/skidbladnir/skidbladnir-launch" ]] ||
    fail 'release transaction launcher must be executable'
  assert_contains "$repo_dir/assets/skidbladnir/skidbladnir-launch" \
    'if [[ -e "$transaction" || -L "$transaction" ]]; then'
  assert_contains "$repo_dir/lib/skidbladnir.sh" 'tailscale serve --bg --yes --https=8443 --set-path=/v1 http://127.0.0.1:7341/v1'
  assert_contains "$repo_dir/lib/skidbladnir.sh" 'tailscale serve --yes --https=8443 --set-path=/ off'
  ! grep -Fq 'serve reset' "$repo_dir/lib/skidbladnir.sh" ||
    fail 'convergence contains a destructive Tailscale Serve reset path'
  assert_contains "$repo_dir/lib/skidbladnir.sh" '--header "If-Match: $etag"'
  assert_contains "$repo_dir/lib/skidbladnir.sh" '/localapi/v0/serve-config'
  assert_contains "$repo_dir/lib/skidbladnir-invite.sh" \
    'Fleet invite ready. It expires in 5 minutes and works once. On the phone, open Skíðblaðnir and tap Connect.'
  assert_contains "$repo_dir/lib/skidbladnir-invite.sh" \
    "Couldn't create the whole fleet invite. Nothing was displayed. Run ./skidbladnir invite again."
  ! grep -Eq -- '--arg[^[:cntrl:]]*(token|result|response|bearer)' "$repo_dir/lib/skidbladnir-invite.sh" ||
    fail 'fleet invitation passes credential material in process arguments'
  assert_contains "$repo_dir/workstation" 'skidbladnir_converge "$(platform_id)"'
  assert_contains "$repo_dir/workstation" 'skidbladnir_require_tmux_runtime "$(platform_id)"'
  ! grep -Fq 'skidbladnir_preflight_tmux_runtime' "$repo_dir/workstation" "$repo_dir/lib/skidbladnir.sh" ||
    fail 'retired tmux version preflight remains'
  ! grep -Fq -- '--ignore tmux' "$repo_dir/lib/packages-arch.sh" ||
    fail 'Arch convergence still excludes tmux from stable upgrades'
  assert_contains "$repo_dir/lib/packages-arch.sh" 'sudo systemctl enable --now sshd.service'
  assert_contains "$repo_dir/lib/packages-arch.sh" 'doctor_pass package.ssh "OpenSSH enabled for fixed tailnet operator access"'
  assert_contains "$repo_dir/lib/packages-macos.sh" 'packages_macos_unpin_tmux'
  assert_contains "$repo_dir/lib/packages-macos.sh" 'brew update'
  assert_contains "$repo_dir/lib/packages-macos.sh" 'HOMEBREW_NO_AUTO_UPDATE=1 brew bundle'
  assert_contains "$repo_dir/ansible/roles/base/tasks/main.yml" 'name: Install latest tmux release'
  assert_contains "$repo_dir/ansible/roles/base/tasks/main.yml" 'state: latest'
  ! grep -Fq 'Verify exact Devbox tmux runtime' "$repo_dir/ansible/roles/base/tasks/main.yml" ||
    fail 'Devbox convergence still enforces an exact tmux version'
  assert_contains "$repo_dir/devbox" 'skidbladnir_doctor devbox'
  assert_contains "$repo_dir/ansible/playbooks/converge.yml" 'role: skidbladnir'
  grep -Fxq 'reconcile-lifetime-digests)' "$repo_dir/skidbladnir" || fail 'exact reconciled lifetime command case missing'
  assert_contains "$repo_dir/skidbladnir" 'accept-host)'
  assert_contains "$repo_dir/lib/skidbladnir-operator.sh" 'SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE=host-acceptance-v1'
  assert_contains "$repo_dir/skidbladnir" 'prepare-reboot | verify-reboot)'
  assert_contains "$repo_dir/lib/skidbladnir-operator.sh" 'SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1'
  assert_contains "$repo_dir/skidbladnir" 'outage | recover)'
  assert_contains "$repo_dir/skidbladnir" 'skidbladnir_operator_require_macbook'
  grep -Fxq 'brew "qrencode"' "$repo_dir/packages/Brewfile" || fail 'MacBook qrencode package missing'
  pass
}

write_release_fixture() {
  local release_dir="$fixture/release"
  local source_sha=1111111111111111111111111111111111111111
  install -d -m 0755 "$release_dir" "$test_bin" "$test_home"
  cat >"$release_dir/skidbladnir" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  version)
    printf 'v1.2.3 1111111111111111111111111111111111111111\n'
    ;;
  machine)
    [[ "$2" == init && "$3" == --file=* ]]
    target="${3#--file=}"
    printf 'mh-11111111111111111111111111111111\n' > "$target"
    chmod 0600 "$target"
    printf 'mh-11111111111111111111111111111111\n'
    ;;
  bearer)
    [[ "$2" == mint && "$3" == --file=* ]]
    target="${3#--file=}"
    printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n' > "$target"
    chmod 0600 "$target"
    printf 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n'
    ;;
  *) exit 64 ;;
esac
EOF
  chmod 0755 "$release_dir/skidbladnir"
  printf '{}\n' >"$release_dir/characters.json"
  jq -n --arg source "$source_sha" \
    '{platform:"linux-amd64",sourceSha:$source,version:"v1.2.3"}' >"$release_dir/release.json"
  tar -czf "$fixture/skidbladnir-linux-amd64.tar.gz" -C "$release_dir" \
    skidbladnir characters.json release.json
  local archive_sha
  archive_sha="$(dev_server_sha256 "$fixture/skidbladnir-linux-amd64.tar.gz")"
  jq -n --arg digest "$archive_sha" --arg source "$source_sha" \
    '{version:"v1.2.3",sourceSha:$source,androidApkSha256:$digest,androidSigningCertAssetSha256:$digest,linuxAmd64Sha256:$digest,darwinArm64Sha256:$digest,sha256SumsAssetSha256:$digest}' \
    >"$fixture/release-pin.json"

  cat >"$fixture/host-config.json" <<EOF
{
  "platform": "Linux",
  "tmux": {"path": "$test_bin/tmux", "testedVersion": "tmux 3.7c"},
  "profiles": [
    {"key":"personal","label":"Codex · Personal","provider":"Codex","command":"$test_home/bin/codex-personal","environment":[{"name":"CODEX_HOME","value":"$test_home/.codex-personal"}],"foregroundSignatures":[{"executableBase":"codex"}],"arguments":[]}
  ]
}
EOF
}

write_runtime_boundaries() {
  cat >"$test_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
original_args=" $* "
request_config=""
if [[ " $* " == *' --config - '* ]]; then
  request_config="$(cat)"
  if [[ "$original_args" == *'/localapi/v0/serve-config '* ]]; then
    if [[ "${1:-}" != -q || "$original_args" != *' --noproxy * '* ]]; then
      printf '%s\n' "$request_config" >"$SKIDBLADNIR_TEST_CURL_LEAK"
    fi
  else
    if [[ "${1:-}" != -q || "$original_args" != *' --noproxy * '* ]]; then
      printf '%s\n' "$request_config" >"$SKIDBLADNIR_TEST_CURL_LEAK"
    fi
    printf 'curl-args' >>"$SKIDBLADNIR_TEST_CALLS"
    printf ' %q' "$@" >>"$SKIDBLADNIR_TEST_CALLS"
    printf '\n' >>"$SKIDBLADNIR_TEST_CALLS"
    url_line=""
    while IFS= read -r line; do
      case "$line" in url\ =*) url_line="$line" ;; esac
    done <<<"$request_config"
    printf 'curl-config %q\n' "$url_line" >>"$SKIDBLADNIR_TEST_CALLS"
    if [[ "$original_args" != *' --output /dev/null '* && -n "${SKIDBLADNIR_TEST_INVENTORY:-}" ]]; then
      printf '%s\n' "$SKIDBLADNIR_TEST_INVENTORY"
    fi
    exit 0
  fi
fi
if [[ "$original_args" == *'/localapi/v0/serve-config '* ]]; then
  if [[ "${1:-}" != -q || "$original_args" != *' --noproxy * '* ]]; then
    printf '%s\n' "$request_config" >"$SKIDBLADNIR_TEST_CURL_LEAK"
  fi
  dump_header=""
  output=""
  data_binary=""
  if_match=""
  socket=""
  url=""
  while (( $# > 0 )); do
    case "$1" in
      --dump-header|-D) dump_header="$2"; shift 2 ;;
      --output|-o) output="$2"; shift 2 ;;
      --data-binary) data_binary="$2"; shift 2 ;;
      --header|-H)
        case "$2" in If-Match:\ *) if_match="${2#If-Match: }" ;; esac
        shift 2
        ;;
      --unix-socket) socket="$2"; shift 2 ;;
      http://*/localapi/v0/serve-config) url="$1"; shift ;;
      *) shift ;;
    esac
  done
  if [[ -n "$socket" ]]; then
    [[ "$socket" == "$SKIDBLADNIR_TEST_TAILSCALE_SOCKET" ]]
    [[ "$url" == http://local-tailscaled.sock/localapi/v0/serve-config ]]
    [[ -z "$request_config" ]]
  else
    [[ "$url" == "http://127.0.0.1:$SKIDBLADNIR_TEST_LOCALAPI_PORT/localapi/v0/serve-config" ]]
    [[ "$request_config" == "user = \":$SKIDBLADNIR_TEST_LOCALAPI_TOKEN\"" ]]
  fi
  if [[ -z "$data_binary" ]]; then
    printf 'curl-localapi GET\n' >>"$SKIDBLADNIR_TEST_CALLS"
    [[ -n "$dump_header" && -n "$output" ]]
    printf 'HTTP/1.1 %s Test\r\n' "${SKIDBLADNIR_TEST_LOCALAPI_GET_STATUS:-200}" >"$dump_header"
    printf 'Content-Type: %s\r\n' "${SKIDBLADNIR_TEST_LOCALAPI_CONTENT_TYPE:-application/json}" >>"$dump_header"
    if [[ "${SKIDBLADNIR_TEST_LOCALAPI_MISSING_ETAG:-0}" == 0 ]]; then
      printf 'Etag: %s\r\n' "$(cat "$SKIDBLADNIR_TEST_SERVE_ETAG")" >>"$dump_header"
    fi
    if [[ "${SKIDBLADNIR_TEST_LOCALAPI_DUPLICATE_ETAG:-0}" != 0 ]]; then
      printf 'ETag: %064d\r\n' 9 >>"$dump_header"
    fi
    printf '\r\n' >>"$dump_header"
    if [[ -n "${SKIDBLADNIR_TEST_LOCALAPI_BODY:-}" ]]; then
      cp "$SKIDBLADNIR_TEST_LOCALAPI_BODY" "$output"
    else
      cp "$SKIDBLADNIR_TEST_SERVE_STATE" "$output"
    fi
    exit 0
  fi
  printf 'curl-localapi POST\n' >>"$SKIDBLADNIR_TEST_CALLS"
  if [[ -n "${SKIDBLADNIR_TEST_LOCALAPI_RACE_STATE:-}" &&
    ! -e "$SKIDBLADNIR_TEST_LOCALAPI_RACE_ONCE" ]]; then
    cp "$SKIDBLADNIR_TEST_LOCALAPI_RACE_STATE" "$SKIDBLADNIR_TEST_SERVE_STATE"
    printf '%064d\n' 2 >"$SKIDBLADNIR_TEST_SERVE_ETAG"
    : >"$SKIDBLADNIR_TEST_LOCALAPI_RACE_ONCE"
  fi
  [[ "${SKIDBLADNIR_TEST_FAIL_LOCALAPI_POST:-0}" == 0 ]]
  [[ "$if_match" == "$(cat "$SKIDBLADNIR_TEST_SERVE_ETAG")" ]]
  [[ "$data_binary" == @* ]]
  cp "${data_binary#@}" "$SKIDBLADNIR_TEST_SERVE_STATE.next"
  mv "$SKIDBLADNIR_TEST_SERVE_STATE.next" "$SKIDBLADNIR_TEST_SERVE_STATE"
  printf '%064d\n' 3 >"$SKIDBLADNIR_TEST_SERVE_ETAG"
  [[ "${SKIDBLADNIR_TEST_FAIL_LOCALAPI_RESPONSE_AFTER_APPLY:-0}" == 0 ]] || exit 75
  [[ -n "$dump_header" ]]
  printf 'HTTP/1.1 %s Test\r\n\r\n' "${SKIDBLADNIR_TEST_LOCALAPI_POST_STATUS:-200}" >"$dump_header"
  exit 0
fi
output=""
while (( $# > 0 )); do
  case "$1" in
    -o|--output) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n "$output" ]]
cp "$SKIDBLADNIR_TEST_ARCHIVE" "$output"
EOF
  cat >"$test_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'systemctl' >> "$SKIDBLADNIR_TEST_CALLS"
printf ' %q' "$@" >> "$SKIDBLADNIR_TEST_CALLS"
printf '\n' >> "$SKIDBLADNIR_TEST_CALLS"
case " $* " in
  *' is-active '*)
    [[ "${SKIDBLADNIR_TEST_IS_ACTIVE_UNAVAILABLE:-0}" == 0 &&
      -f "$SKIDBLADNIR_TEST_SERVICE_STATE" ]]
    ;;
  *' is-enabled '*) [[ -f "$SKIDBLADNIR_TEST_SERVICE_STATE" ]] ;;
  *' enable --now '*)
    if [[ ! -f "$SKIDBLADNIR_TEST_SERVICE_STATE" ]]; then
      touch "$SKIDBLADNIR_TEST_SERVICE_STATE"
      "$SKIDBLADNIR_TEST_INSTALLED_BINARY" version >"$SKIDBLADNIR_TEST_SERVICE_VERSION"
    fi
    ;;
  *' restart '*)
    if [[ -n "${SKIDBLADNIR_TEST_FAIL_RESTART_ONCE:-}" &&
      ! -e "$SKIDBLADNIR_TEST_FAIL_RESTART_ONCE" ]]; then
      : >"$SKIDBLADNIR_TEST_FAIL_RESTART_ONCE"
      exit 73
    fi
    "$SKIDBLADNIR_TEST_INSTALLED_BINARY" version >"$SKIDBLADNIR_TEST_SERVICE_VERSION"
    ;;
esac
EOF
  cat >"$test_bin/loginctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' show-user '* ]]; then printf 'yes\n'; fi
EOF
  cat >"$test_bin/sudo" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec "$@"
EOF
  cat >"$test_bin/tailscale" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'tailscale' >> "$SKIDBLADNIR_TEST_CALLS"
printf ' %q' "$@" >> "$SKIDBLADNIR_TEST_CALLS"
printf '\n' >> "$SKIDBLADNIR_TEST_CALLS"
case "${1:-} ${2:-}" in
  'status --json')
    if [[ -n "${SKIDBLADNIR_TEST_TAILSCALE_STATUS_SEQUENCE:-}" ]]; then
      count=0
      if [[ -e "$SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT" ]]; then
        count="$(cat "$SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT")"
      fi
      count=$((count + 1))
      printf '%s\n' "$count" >"$SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT"
      awk -v wanted="$count" 'NR == wanted { print; found = 1 } END { exit !found }' \
        "$SKIDBLADNIR_TEST_TAILSCALE_STATUS_SEQUENCE"
    elif [[ -n "${SKIDBLADNIR_TEST_TAILSCALE_STATUS:-}" ]]; then
      printf '%s\n' "$SKIDBLADNIR_TEST_TAILSCALE_STATUS"
    else
      printf '%s\n' '{"BackendState":"Running","Self":{"DNSName":"current.example.ts.net."}}'
    fi
    ;;
  'debug local-creds')
    if [[ -n "${SKIDBLADNIR_TEST_LOCAL_CREDS:-}" ]]; then
      printf '%s\n' "$SKIDBLADNIR_TEST_LOCAL_CREDS"
    else
      printf 'curl --unix-socket %s http://local-tailscaled.sock/localapi/v0/status\n' \
        "$SKIDBLADNIR_TEST_TAILSCALE_SOCKET"
    fi
    ;;
  'serve status')
    if [[ -n "${SKIDBLADNIR_TEST_SERVE_SECOND_STATUS:-}" &&
      -n "${SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE:-}" &&
      -e "$SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE" ]]; then
      if [[ -n "${SKIDBLADNIR_TEST_SERVE_SECOND_STATE:-}" ]]; then
        cp "$SKIDBLADNIR_TEST_SERVE_SECOND_STATE" "$SKIDBLADNIR_TEST_SERVE_STATE"
      fi
      printf '%s\n' "$SKIDBLADNIR_TEST_SERVE_SECOND_STATUS"
    elif [[ -n "${SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE:-}" ]]; then
      : >"$SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE"
      printf '%s\n' "$SKIDBLADNIR_TEST_SERVE_STATUS"
    elif [[ -n "${SKIDBLADNIR_TEST_SERVE_STATE:-}" ]]; then
      cat "$SKIDBLADNIR_TEST_SERVE_STATE"
    elif [[ -n "${SKIDBLADNIR_TEST_SERVE_STATUS:-}" ]]; then
      printf '%s\n' "$SKIDBLADNIR_TEST_SERVE_STATUS"
    else
      printf '%s\n' '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}}}'
    fi
    ;;
  'serve --bg')
    [[ "${SKIDBLADNIR_TEST_FAIL_SERVE_APPLY:-0}" == 0 ]] || exit 74
    if [[ -n "${SKIDBLADNIR_TEST_SERVE_STATE:-}" ]]; then
      jq -c --arg host "$SKIDBLADNIR_TEST_SERVE_HOST" \
        '.TCP["8443"] = {HTTPS:true} |
          .Web[$host + ":8443"] = {Handlers:{"/v1":{Proxy:"http://127.0.0.1:7341/v1"}}}' \
        "$SKIDBLADNIR_TEST_SERVE_STATE" \
        >"$SKIDBLADNIR_TEST_SERVE_STATE.next"
      mv "$SKIDBLADNIR_TEST_SERVE_STATE.next" "$SKIDBLADNIR_TEST_SERVE_STATE"
    fi
    ;;
esac
EOF
  cat >"$test_bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -V ]]
printf '%s\n' "${SKIDBLADNIR_TEST_TMUX_VERSION:-tmux 3.7c}"
EOF
  cat >"$test_bin/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
target="${!#}"
if [[ -n "${SKIDBLADNIR_TEST_FAIL_INSTALL_TARGET:-}" &&
  "$target" == *"${SKIDBLADNIR_TEST_FAIL_INSTALL_TARGET}"* &&
  ! -e "$SKIDBLADNIR_TEST_FAIL_INSTALL_ONCE" ]]; then
  : >"$SKIDBLADNIR_TEST_FAIL_INSTALL_ONCE"
  exit 73
fi
exec /usr/bin/install "$@"
EOF
  chmod 0755 "$test_bin"/*
}

test_converge_and_doctor() {
  write_release_fixture
  write_runtime_boundaries
  export SKIDBLADNIR_TEST_ARCHIVE="$fixture/skidbladnir-linux-amd64.tar.gz"
  export SKIDBLADNIR_TEST_CALLS="$fixture/runtime-calls"
  export SKIDBLADNIR_TEST_CURL_LEAK="$fixture/ambient-curl-leak"
  export SKIDBLADNIR_TEST_SERVICE_STATE="$fixture/service-active"
  export SKIDBLADNIR_TEST_SERVICE_VERSION="$fixture/service-version"
  export SKIDBLADNIR_TEST_INSTALLED_BINARY="$test_home/.local/bin/skidbladnir"
  : >"$SKIDBLADNIR_TEST_CALLS"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/doctor.sh
  source "$repo_dir/lib/doctor.sh"
  # shellcheck source=lib/skidbladnir.sh
  source "$repo_dir/lib/skidbladnir.sh"
  assert_eq dev-server "$(skidbladnir_remote_target DevServer)" \
    'fixed DevServer SSH target'
  assert_eq nnandal@arch "$(skidbladnir_remote_target Arch)" \
    'fixed Arch SSH account and alias'
  # dev_server_home reads this shared library seam.
  # shellcheck disable=SC2034
  dev_server_home_dir="$test_home"
  # shellcheck disable=SC2034
  skidbladnir_release_pin_file="$fixture/release-pin.json"
  skidbladnir_host_config_source() { printf '%s\n' "$fixture/host-config.json"; }
  skidbladnir_tailscale_cli() { printf '%s\n' "$test_bin/tailscale"; }
  skidbladnir_runtime_os() { printf 'Linux\n'; }
  skidbladnir_claude_plugin_topology_is_exact \
    "$repo_dir/assets/skidbladnir/claude-agent-identity" ||
    fail 'deployment source Claude plugin topology is not the exact seven-node tree'

  if skidbladnir_observed_tmux_version "$fixture/missing-tmux" >/dev/null 2>&1; then
    fail 'missing tmux executable was accepted'
  fi
  export SKIDBLADNIR_TEST_TMUX_VERSION=$'tmux 3.8\nextra'
  if skidbladnir_observed_tmux_version "$test_bin/tmux" >/dev/null 2>&1; then
    fail 'multiline tmux version output was accepted'
  fi
  unset SKIDBLADNIR_TEST_TMUX_VERSION

  printf 'owned source\n' >"$fixture/owned-source"
  printf 'unrelated target\n' >"$fixture/unrelated-target"
  ln -s "$fixture/unrelated-target" "$fixture/owned-target"
  # shellcheck disable=SC2034
  skidbladnir_changed=0
  if (skidbladnir_install_owned "$fixture/owned-source" \
    "$fixture/owned-target" 0644) >/dev/null 2>&1; then
    fail 'owned installation replaced an unexpected symlink target'
  fi
  assert_eq 'unrelated target' "$(cat "$fixture/unrelated-target")" \
    'unexpected symlink referent preserved'
  rm -f -- "$fixture/owned-target"

  cp "$skidbladnir_release_pin_file" "$fixture/release-pin.valid.json"
  jq '.version = "v01.2.3"' "$fixture/release-pin.valid.json" >"$skidbladnir_release_pin_file"
  if skidbladnir_release_values arch >/dev/null 2>&1; then
    fail 'release pin accepted a noncanonical leading-zero version'
  fi
  mv "$fixture/release-pin.valid.json" "$skidbladnir_release_pin_file"
  cp "$skidbladnir_release_pin_file" "$fixture/release-pin.valid.json"
  local release_case_version release_case_source release_case_expected release_case_observed
  while read -r release_case_version release_case_source release_case_expected; do
    jq --arg version "$release_case_version" --arg source "$release_case_source" \
      '.version = $version | .sourceSha = $source' \
      "$fixture/release-pin.valid.json" >"$skidbladnir_release_pin_file"
    if skidbladnir_release_values arch >/dev/null 2>&1; then
      release_case_observed=accept
    else
      release_case_observed=reject
    fi
    assert_eq "$release_case_expected" "$release_case_observed" \
      "Skidbladnir release compatibility boundary for $release_case_version"
  done <<'RELEASE_CASES'
v0.2.9 40b29223c0e474ec1c5e910cf8b9ad8a746a2602 reject
v0.2.10 96da47a1239c8b3e96fbcc8998ad3eba23fa69fa accept
v0.3.0 3333333333333333333333333333333333333333 accept
RELEASE_CASES
  mv "$fixture/release-pin.valid.json" "$skidbladnir_release_pin_file"
  cp "$skidbladnir_release_pin_file" "$fixture/release-pin.valid.json"
  sed 's/"version": "v1.2.3"/"version": "v1.2.3", "version": "v1.2.3"/' \
    "$fixture/release-pin.valid.json" >"$skidbladnir_release_pin_file"
  if skidbladnir_release_values arch >/dev/null 2>&1; then
    fail 'release pin accepted a duplicate version member'
  fi
  mv "$fixture/release-pin.valid.json" "$skidbladnir_release_pin_file"

  local old_path="$PATH"
  local installed_plugin="$test_home/.local/share/skidbladnir/claude-agent-identity"
  install -d -m 0755 "$installed_plugin/.claude-plugin"
  PATH="$test_bin:$PATH"
  export PATH
  skidbladnir_converge arch
  local handle_before bearer_before
  handle_before="$(cat "$test_home/.config/skidbladnir/machine-handle")"
  bearer_before="$(cat "$test_home/.config/skidbladnir/bearer")"
  assert_eq mh-11111111111111111111111111111111 "$handle_before" 'created machine handle'
  assert_eq AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "$bearer_before" 'created bearer'
  skidbladnir_claude_plugin_topology_is_exact "$installed_plugin" ||
    fail 'partial Claude plugin tree did not converge to the exact seven-node tree'
  : >"$SKIDBLADNIR_TEST_CALLS"
  skidbladnir_converge arch
  assert_eq "$handle_before" "$(cat "$test_home/.config/skidbladnir/machine-handle")" 'preserved machine handle'
  assert_eq "$bearer_before" "$(cat "$test_home/.config/skidbladnir/bearer")" 'preserved bearer'
  [[ -s "$test_home/.local/share/skidbladnir/release-bundle.tar.gz" ]] ||
    fail 'verified release bundle was not retained for doctor comparisons'
  ! grep -Fq 'serve reset' "$SKIDBLADNIR_TEST_CALLS" || fail 'runtime invoked Tailscale Serve reset'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'tailscale serve --bg --yes --https=8443 --set-path=/v1 http://127.0.0.1:7341/v1'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'systemctl --user enable --now skidbladnir.service'
  ! grep -Fq 'systemctl --user restart skidbladnir.service' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'unchanged active Linux service was restarted'

  local -a plugin_owned_targets=(
    "$installed_plugin/.claude-plugin/plugin.json"
    "$installed_plugin/hooks/hooks.json"
    "$installed_plugin/bin/agent-hook"
  )
  local plugin_owned_before unexpected_plugin_entry topology_status
  plugin_owned_before="$(deployment_owned_snapshot "${plugin_owned_targets[@]}")"
  unexpected_plugin_entry="$installed_plugin/.mcp.json"
  printf '{}\n' >"$unexpected_plugin_entry"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/plugin-extra-doctor" || true
  assert_contains "$fixture/plugin-extra-doctor" 'FAIL  skidbladnir.config'
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  skidbladnir_converge arch >/dev/null 2>"$fixture/plugin-extra-converge-error"
  topology_status=$?
  set -e
  [[ "$topology_status" -ne 0 ]] ||
    fail 'convergence accepted an unmanaged Claude plugin capability'
  assert_contains "$fixture/plugin-extra-converge-error" \
    'Skidbladnir Claude plugin contains an unmanaged entry:'
  assert_eq '{}' "$(cat "$unexpected_plugin_entry")" \
    'failed convergence preserved the unmanaged Claude plugin entry'
  assert_eq "$plugin_owned_before" \
    "$(deployment_owned_snapshot "${plugin_owned_targets[@]}")" \
    'failed plugin topology preflight preserved every owned plugin file'
  ! grep -Eq '^(systemctl|tailscale)' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'failed plugin topology preflight reached a host mutation boundary'
  /bin/unlink "$unexpected_plugin_entry"

  skidbladnir_begin_release_transaction arch "$test_home"
  printf '{}\n' >"$unexpected_plugin_entry"
  set +e
  (skidbladnir_commit_release_transaction arch "$test_home" \
    "$fixture/release" "$fixture/skidbladnir-linux-amd64.tar.gz") \
    >/dev/null 2>"$fixture/plugin-extra-commit-error"
  topology_status=$?
  set -e
  [[ "$topology_status" -ne 0 ]] ||
    fail 'release transaction committed a concurrently widened Claude plugin'
  assert_contains "$fixture/plugin-extra-commit-error" \
    'Skidbladnir Claude plugin topology changed during release transaction'
  skidbladnir_recover_release_transaction arch "$test_home"
  assert_eq '{}' "$(cat "$unexpected_plugin_entry")" \
    'release rollback preserved the unknown Claude plugin entry'
  assert_eq "$plugin_owned_before" \
    "$(deployment_owned_snapshot "${plugin_owned_targets[@]}")" \
    'release rollback did not restore every owned plugin file'
  [[ ! -e "$test_home/.local/share/skidbladnir/.release-transaction" ]] ||
    fail 'plugin topology rollback left its release transaction journal'
  /bin/unlink "$unexpected_plugin_entry"

  export SKIDBLADNIR_TEST_SERVE_STATUS='{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:7341"}}}}}'
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'tailscale serve --yes --https=8443 --set-path=/ off'
  unset SKIDBLADNIR_TEST_SERVE_STATUS

  local duplicate_serve_status='{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":{}}'
  local desired_serve_status='{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}}}'
  local raced_serve_status='{"TCP":{"8443":{"HTTPS":true},"9443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"other.example.ts.net:9443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}}}'
  local serve_state="$fixture/serve-state.json"
  local serve_etag="$fixture/serve-etag"
  test_socket_dir="$(mktemp -d /tmp/dev-server-skid-socket.XXXXXX)"
  local tailscale_socket="$test_socket_dir/tailscaled.sock"
  local localapi_body="$fixture/localapi-body.json"
  local serve_tmp="$fixture/serve-tmp"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket, sys; sock = socket.socket(socket.AF_UNIX); sock.bind(sys.argv[1]); sock.close()' \
      "$tailscale_socket"
  else
    ruby -rsocket -e 'server = UNIXServer.new(ARGV.fetch(0)); server.close' "$tailscale_socket"
  fi
  export SKIDBLADNIR_TEST_TAILSCALE_SOCKET="$tailscale_socket"
  export SKIDBLADNIR_TEST_SERVE_ETAG="$serve_etag"
  export SKIDBLADNIR_TEST_SERVE_HOST=current.example.ts.net
  export SKIDBLADNIR_TEST_LOCALAPI_PORT=41112
  export SKIDBLADNIR_TEST_LOCALAPI_TOKEN=macToken_0123456789abcdef
  install -d -m 0700 "$serve_tmp"
  export TMPDIR="$serve_tmp"
  printf '%064d\n' 1 >"$serve_etag"
  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%s\n' '{"AllowFunnel":{},"Web":{"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"TCP":{"8443":{"HTTPS":true}}}' >"$localapi_body"
  export SKIDBLADNIR_TEST_SERVE_STATE="$serve_state"
  export SKIDBLADNIR_TEST_LOCALAPI_BODY="$localapi_body"

  local stale_v1_serve_status='{"TCP":{"8443":{"HTTPS":true}},"Web":{"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":{}}'
  local stale_root_serve_status='{"TCP":{"8443":{"HTTPS":true}},"Web":{"retired.example.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:7341"}}}},"AllowFunnel":{}}'
  assert_stale_serve_reconciled() {
    local label="$1"
    local platform="$2"
    local runtime="$3"
    local stale_status="$4"
    skidbladnir_runtime_os() { printf '%s\n' "$runtime"; }
    if [[ "$platform" == macos ]]; then
      export SKIDBLADNIR_TEST_LOCAL_CREDS="curl -u:$SKIDBLADNIR_TEST_LOCALAPI_TOKEN http://localhost:$SKIDBLADNIR_TEST_LOCALAPI_PORT/localapi/v0/status"
    else
      unset SKIDBLADNIR_TEST_LOCAL_CREDS
    fi
    printf '%s\n' "$stale_status" >"$serve_state"
    printf '%064d\n' 1 >"$serve_etag"
    unset SKIDBLADNIR_TEST_LOCALAPI_BODY
    : >"$SKIDBLADNIR_TEST_CALLS"
    skidbladnir_configure_serve "$test_bin/tailscale" "$platform"
    jq -e --argjson desired "$desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
      fail "$label stale Serve hostname was not replaced atomically"
    assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi GET'
    assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
    ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "$label stale Serve hostname fell through to additive CLI mutation"
    ! grep -Fq 'tailscale serve --yes' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "$label stale Serve root mapping fell through to current-host CLI removal"
  }
  printf '%s\n' "$stale_v1_serve_status" >"$serve_state"
  unset SKIDBLADNIR_TEST_LOCALAPI_BODY
  doctor_reset
  skidbladnir_doctor arch >"$fixture/single-stale-serve-doctor" || true
  assert_contains "$fixture/single-stale-serve-doctor" 'FAIL  skidbladnir.serve'
  assert_stale_serve_reconciled linux-v1 arch Linux "$stale_v1_serve_status"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/single-stale-repaired-doctor"
  assert_contains "$fixture/single-stale-repaired-doctor" 'PASS  skidbladnir.serve'
  assert_stale_serve_reconciled linux-root arch Linux "$stale_root_serve_status"
  assert_stale_serve_reconciled macos-v1 macos Darwin "$stale_v1_serve_status"
  assert_stale_serve_reconciled macos-root macos Darwin "$stale_root_serve_status"
  unset -f assert_stale_serve_reconciled
  unset SKIDBLADNIR_TEST_LOCAL_CREDS
  skidbladnir_runtime_os() { printf 'Linux\n'; }

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_LOCALAPI_BODY="$localapi_body"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/duplicate-serve-doctor" || true
  assert_contains "$fixture/duplicate-serve-doctor" 'FAIL  skidbladnir.serve'
  : >"$SKIDBLADNIR_TEST_CALLS"
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  unset SKIDBLADNIR_TEST_LOCALAPI_BODY
  printf '%s\n' \
    'tailscale status --json' \
    'tailscale serve status --json' \
    'tailscale debug local-creds' \
    'curl-localapi GET' \
    'tailscale status --json' \
    'curl-localapi POST' \
    'tailscale status --json' \
    'tailscale serve status --json' \
    >"$fixture/expected-duplicate-serve-calls"
  cmp -s "$fixture/expected-duplicate-serve-calls" "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'owned duplicate Serve hostname repair did not use atomic LocalAPI compare-and-swap'
  jq -e --argjson desired "$desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
    fail 'owned duplicate Serve hostname repair did not leave one canonical mapping'
  doctor_reset
  skidbladnir_doctor arch >"$fixture/repaired-serve-doctor"
  assert_contains "$fixture/repaired-serve-doctor" 'PASS  skidbladnir.serve'
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  assert_eq 1 "$(grep -Fc 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS")" \
    'canonical Serve state was reconciled again'
  ! grep -Fq 'serve reset' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'duplicate repair invoked a destructive Serve reset'
  unset SKIDBLADNIR_TEST_SERVE_STATE

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064s\n' e | tr ' ' e >"$serve_etag"
  export SKIDBLADNIR_TEST_SERVE_STATE="$serve_state"
  export SKIDBLADNIR_TEST_LOCAL_CREDS="curl -u:$SKIDBLADNIR_TEST_LOCALAPI_TOKEN http://localhost:$SKIDBLADNIR_TEST_LOCALAPI_PORT/localapi/v0/status"
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS='{"BackendState":"Running","Self":{"DNSName":"current.example.ts.net."},"Peer":{"peer-secret":{"UserID":12345}}}'
  skidbladnir_runtime_os() { printf 'Darwin\n'; }
  : >"$SKIDBLADNIR_TEST_CALLS"
  local mac_cas_xtrace="$fixture/mac-cas-xtrace"
  {
    set -x
    skidbladnir_configure_serve "$test_bin/tailscale" macos
    set +x
  } 2>"$mac_cas_xtrace"
  jq -e --argjson desired "$desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
    fail 'macOS token LocalAPI repair did not leave one canonical mapping'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi GET'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
  for private_value in \
    "$SKIDBLADNIR_TEST_LOCALAPI_TOKEN" "$tailscale_socket" \
    "$(printf '%064s' e | tr ' ' e)" 'retired.example.ts.net' 'peer-secret'; do
    ! grep -Fq "$private_value" "$mac_cas_xtrace" ||
      fail 'duplicate Serve repair exposed private state under xtrace'
  done
  [[ ! -e "$SKIDBLADNIR_TEST_CURL_LEAK" ]] ||
    fail 'macOS token LocalAPI repair honored ambient curl state'
  [[ -z "$(find "$serve_tmp" -mindepth 1 -print -quit)" ]] ||
    fail 'duplicate Serve repair left temporary files behind'
  skidbladnir_runtime_os() { printf 'Linux\n'; }
  unset SKIDBLADNIR_TEST_LOCAL_CREDS SKIDBLADNIR_TEST_SERVE_STATE \
    SKIDBLADNIR_TEST_TAILSCALE_STATUS

  assert_serve_reconcile_refused() {
    local label="$1"
    local status_json="$2"
    local status
    export SKIDBLADNIR_TEST_SERVE_STATUS="$status_json"
    : >"$SKIDBLADNIR_TEST_CALLS"
    set +e
    (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
      >"$fixture/refused-serve-$label-output" 2>"$fixture/refused-serve-$label-error"
    status=$?
    set -e
    unset SKIDBLADNIR_TEST_SERVE_STATUS
    [[ "$status" -ne 0 ]] || fail "$label Serve state permitted duplicate reconciliation"
    ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "$label Serve state reached atomic replacement"
    ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "$label Serve state was mutated after reconciliation refusal"
  }
  assert_serve_reconcile_refused unrelated-port \
    '{"TCP":{"8443":{"HTTPS":true},"9443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"other.example.ts.net:9443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}},"AllowFunnel":{}}'
  assert_serve_reconcile_refused wrong-proxy \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:9000/v1"}}}},"AllowFunnel":{}}'
  assert_serve_reconcile_refused funnel-true \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":{"current.example.ts.net:8443":true}}'
  assert_serve_reconcile_refused funnel-false \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":{"unrelated.example.ts.net:443":false}}'
  assert_serve_reconcile_refused funnel-null \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":null}'
  assert_serve_reconcile_refused funnel-false-marker \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":false}'
  assert_serve_reconcile_refused services \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Services":{"svc:other":{"TCP":{"443":{"HTTPS":true}}}}}'
  assert_serve_reconcile_refused services-null \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Services":null}'
  assert_serve_reconcile_refused services-false \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Services":false}'
  assert_serve_reconcile_refused foreground \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Foreground":{"session":{"TCP":{"443":{"HTTPS":true}}}}}'
  assert_serve_reconcile_refused foreground-null \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Foreground":null}'
  assert_serve_reconcile_refused foreground-false \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Foreground":false}'
  assert_serve_reconcile_refused unknown-field \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"Unknown":{}}'
  assert_serve_reconcile_refused malformed '[]'
  unset -f assert_serve_reconcile_refused

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_SERVE_STATE="$serve_state"
  export SKIDBLADNIR_TEST_FAIL_LOCALAPI_POST=1
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/failed-serve-cas-output" 2>"$fixture/failed-serve-cas-error"
  local failed_serve_cas_status=$?
  set -e
  unset SKIDBLADNIR_TEST_FAIL_LOCALAPI_POST
  [[ "$failed_serve_cas_status" -ne 0 ]] || fail 'failed Serve compare-and-swap reported success'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
  jq -e --argjson duplicate "$duplicate_serve_status" '. == $duplicate' "$serve_state" >/dev/null ||
    fail 'failed Serve compare-and-swap changed the prior configuration'
  ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'failed Serve compare-and-swap proceeded to CLI mutation'
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  doctor_reset
  skidbladnir_doctor arch >"$fixture/retried-serve-cas-doctor"
  assert_contains "$fixture/retried-serve-cas-doctor" 'PASS  skidbladnir.serve'

  local post_status post_status_result
  for post_status in 204 302; do
    printf '%s\n' "$duplicate_serve_status" >"$serve_state"
    printf '%064d\n' 1 >"$serve_etag"
    export SKIDBLADNIR_TEST_LOCALAPI_POST_STATUS="$post_status"
    : >"$SKIDBLADNIR_TEST_CALLS"
    set +e
    (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
      >"$fixture/localapi-post-$post_status-output" \
      2>"$fixture/localapi-post-$post_status-error"
    post_status_result=$?
    set -e
    unset SKIDBLADNIR_TEST_LOCALAPI_POST_STATUS
    [[ "$post_status_result" -ne 0 ]] ||
      fail "LocalAPI POST HTTP $post_status response was accepted"
    assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
    jq -e --argjson desired "$desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
      fail "LocalAPI POST HTTP $post_status did not preserve the applied canonical state"
    ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "LocalAPI POST HTTP $post_status failure fell back to CLI mutation"
    skidbladnir_configure_serve "$test_bin/tailscale" arch
    assert_eq 1 "$(grep -Fc 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS")" \
      "retry after LocalAPI POST HTTP $post_status repeated atomic replacement"
  done

  local post_cas_drift_serve_status='{"TCP":{"8443":{"HTTPS":true},"9443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"other.example.ts.net:9443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}}}'
  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%s\n' "$post_cas_drift_serve_status" >"$fixture/post-cas-drift-state.json"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_SERVE_STATUS="$duplicate_serve_status"
  export SKIDBLADNIR_TEST_SERVE_SECOND_STATUS="$post_cas_drift_serve_status"
  export SKIDBLADNIR_TEST_SERVE_SECOND_STATE="$fixture/post-cas-drift-state.json"
  export SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE="$fixture/post-cas-drift-status-read-once"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/post-cas-drift-output" 2>"$fixture/post-cas-drift-error"
  local post_cas_drift_result=$?
  set -e
  unset SKIDBLADNIR_TEST_SERVE_STATUS SKIDBLADNIR_TEST_SERVE_SECOND_STATUS \
    SKIDBLADNIR_TEST_SERVE_SECOND_STATE SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE
  [[ "$post_cas_drift_result" -ne 0 ]] || fail 'post-CAS Serve drift reported success'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
  jq -e --argjson drift "$post_cas_drift_serve_status" '. == $drift' "$serve_state" >/dev/null ||
    fail 'post-CAS Serve drift was not preserved'
  ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'post-CAS Serve drift failure fell back to CLI mutation'
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  assert_eq 1 "$(grep -Fc 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS")" \
    'retry after post-CAS Serve drift repeated atomic replacement'
  jq -e --argjson drift "$post_cas_drift_serve_status" '. == $drift' "$serve_state" >/dev/null ||
    fail 'retry after post-CAS Serve drift changed unrelated Serve state'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_LOCAL_CREDS="curl -u:$SKIDBLADNIR_TEST_LOCALAPI_TOKEN http://localhost:$SKIDBLADNIR_TEST_LOCALAPI_PORT/localapi/v0/status"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/unsupported-local-creds-output" 2>"$fixture/unsupported-local-creds-error"
  local unsupported_local_creds_status=$?
  set -e
  unset SKIDBLADNIR_TEST_LOCAL_CREDS
  [[ "$unsupported_local_creds_status" -ne 0 ]] || fail 'Linux accepted token LocalAPI credentials'
  ! grep -Fq 'curl-localapi' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'Linux token LocalAPI credentials reached curl'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  skidbladnir_runtime_os() { printf 'Darwin\n'; }
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" macos) \
    >"$fixture/macos-unix-creds-output" 2>"$fixture/macos-unix-creds-error"
  local macos_unix_creds_status=$?
  set -e
  skidbladnir_runtime_os() { printf 'Linux\n'; }
  [[ "$macos_unix_creds_status" -ne 0 ]] || fail 'macOS accepted Unix-socket LocalAPI credentials'
  ! grep -Fq 'curl-localapi' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'macOS Unix-socket LocalAPI credentials reached curl'

  local alternate_duplicate_serve_status='{"AllowFunnel":{},"TCP":{"8443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"older.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"retired.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}}}'
  printf '%s\n' "$alternate_duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_SERVE_STATUS="$duplicate_serve_status"
  export SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE="$fixture/snapshot-status-read-once"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/mismatched-snapshot-output" 2>"$fixture/mismatched-snapshot-error"
  local mismatched_snapshot_status=$?
  set -e
  unset SKIDBLADNIR_TEST_SERVE_STATUS SKIDBLADNIR_TEST_SERVE_STATUS_READ_ONCE
  [[ "$mismatched_snapshot_status" -ne 0 ]] ||
    fail 'LocalAPI state different from the approved CLI snapshot was accepted'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi GET'
  ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'mismatched CLI and LocalAPI Serve snapshots reached mutation'
  jq -e --argjson alternate "$alternate_duplicate_serve_status" '. == $alternate' "$serve_state" >/dev/null ||
    fail 'snapshot mismatch changed the LocalAPI Serve state'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  printf '%s\n%s\n' "$duplicate_serve_status" "$duplicate_serve_status" \
    >"$fixture/multiple-localapi-documents"
  export SKIDBLADNIR_TEST_LOCALAPI_BODY="$fixture/multiple-localapi-documents"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/multiple-localapi-documents-output" 2>"$fixture/multiple-localapi-documents-error"
  local multiple_localapi_documents_status=$?
  set -e
  unset SKIDBLADNIR_TEST_LOCALAPI_BODY
  [[ "$multiple_localapi_documents_status" -ne 0 ]] ||
    fail 'multiple LocalAPI Serve JSON documents were accepted'
  ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'multiple LocalAPI Serve JSON documents reached mutation'

  local metadata_case metadata_status
  for metadata_case in non-200 missing-etag duplicate-etag wrong-content-type; do
    printf '%s\n' "$duplicate_serve_status" >"$serve_state"
    printf '%064d\n' 1 >"$serve_etag"
    case "$metadata_case" in
    non-200) export SKIDBLADNIR_TEST_LOCALAPI_GET_STATUS=302 ;;
    missing-etag) export SKIDBLADNIR_TEST_LOCALAPI_MISSING_ETAG=1 ;;
    duplicate-etag) export SKIDBLADNIR_TEST_LOCALAPI_DUPLICATE_ETAG=1 ;;
    wrong-content-type) export SKIDBLADNIR_TEST_LOCALAPI_CONTENT_TYPE=text/plain ;;
    esac
    : >"$SKIDBLADNIR_TEST_CALLS"
    set +e
    (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
      >"$fixture/localapi-$metadata_case-output" 2>"$fixture/localapi-$metadata_case-error"
    metadata_status=$?
    set -e
    unset SKIDBLADNIR_TEST_LOCALAPI_GET_STATUS SKIDBLADNIR_TEST_LOCALAPI_MISSING_ETAG \
      SKIDBLADNIR_TEST_LOCALAPI_DUPLICATE_ETAG SKIDBLADNIR_TEST_LOCALAPI_CONTENT_TYPE
    [[ "$metadata_status" -ne 0 ]] || fail "$metadata_case LocalAPI metadata was accepted"
    ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "$metadata_case LocalAPI metadata reached mutation"
  done

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  dd if=/dev/zero of="$fixture/oversized-localapi-body" bs=65537 count=1 2>/dev/null
  export SKIDBLADNIR_TEST_LOCALAPI_BODY="$fixture/oversized-localapi-body"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/oversized-localapi-body-output" 2>"$fixture/oversized-localapi-body-error"
  local oversized_localapi_body_status=$?
  set -e
  unset SKIDBLADNIR_TEST_LOCALAPI_BODY
  [[ "$oversized_localapi_body_status" -ne 0 ]] || fail 'oversized LocalAPI Serve body was accepted'
  ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'oversized LocalAPI Serve body reached mutation'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS='{"BackendState":"Running","Self":{"DNSName":"renamed.example.ts.net."}}'
  : >"$SKIDBLADNIR_TEST_CALLS"
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  unset SKIDBLADNIR_TEST_TAILSCALE_STATUS
  local renamed_desired_serve_status='{"TCP":{"8443":{"HTTPS":true}},"Web":{"renamed.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}}}'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi GET'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
  jq -e --argjson desired "$renamed_desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
    fail 'all-stale owned Serve hostnames were not replaced with the current hostname'
  ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'all-stale owned Serve hostnames fell through to additive CLI mutation'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf 'not-an-etag\n' >"$serve_etag"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/invalid-etag-output" 2>"$fixture/invalid-etag-error"
  local invalid_etag_status=$?
  set -e
  [[ "$invalid_etag_status" -ne 0 ]] || fail 'invalid LocalAPI ETag was accepted'
  ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'invalid LocalAPI ETag reached mutation'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  printf '%s\n' \
    '{"BackendState":"Running","Self":{"DNSName":"current.example.ts.net."}}' \
    '{"BackendState":"Running","Self":{"DNSName":"renamed.example.ts.net."}}' \
    >"$fixture/pre-post-hostname-sequence"
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS_SEQUENCE="$fixture/pre-post-hostname-sequence"
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT="$fixture/pre-post-hostname-count"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/pre-post-hostname-output" 2>"$fixture/pre-post-hostname-error"
  local pre_post_hostname_status=$?
  set -e
  unset SKIDBLADNIR_TEST_TAILSCALE_STATUS_SEQUENCE SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT
  [[ "$pre_post_hostname_status" -ne 0 ]] ||
    fail 'hostname change before LocalAPI POST was accepted'
  ! grep -Fq 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'hostname change before LocalAPI POST reached mutation'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  printf '%s\n' \
    '{"BackendState":"Running","Self":{"DNSName":"current.example.ts.net."}}' \
    '{"BackendState":"Running","Self":{"DNSName":"current.example.ts.net."}}' \
    '{"BackendState":"Running","Self":{"DNSName":"renamed.example.ts.net."}}' \
    >"$fixture/post-hostname-sequence"
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS_SEQUENCE="$fixture/post-hostname-sequence"
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT="$fixture/post-hostname-count"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/post-hostname-output" 2>"$fixture/post-hostname-error"
  local post_hostname_status=$?
  set -e
  unset SKIDBLADNIR_TEST_TAILSCALE_STATUS_SEQUENCE SKIDBLADNIR_TEST_TAILSCALE_STATUS_COUNT
  [[ "$post_hostname_status" -ne 0 ]] ||
    fail 'hostname change after LocalAPI POST reported success'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-localapi POST'
  jq -e --argjson desired "$desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
    fail 'hostname postcondition failure did not preserve the applied canonical state'
  ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'hostname postcondition failure fell back to CLI mutation'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  export SKIDBLADNIR_TEST_FAIL_LOCALAPI_RESPONSE_AFTER_APPLY=1
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/lost-post-response-output" 2>"$fixture/lost-post-response-error"
  local lost_post_response_status=$?
  set -e
  unset SKIDBLADNIR_TEST_FAIL_LOCALAPI_RESPONSE_AFTER_APPLY
  [[ "$lost_post_response_status" -ne 0 ]] ||
    fail 'lost LocalAPI POST response reported success'
  jq -e --argjson desired "$desired_serve_status" '. == $desired' "$serve_state" >/dev/null ||
    fail 'lost LocalAPI POST response did not preserve the applied canonical state'
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  assert_eq 1 "$(grep -Fc 'curl-localapi POST' "$SKIDBLADNIR_TEST_CALLS")" \
    'retry after a lost POST response repeated atomic replacement'

  printf '%s\n' "$duplicate_serve_status" >"$serve_state"
  printf '%064d\n' 1 >"$serve_etag"
  printf '%s\n' "$raced_serve_status" >"$fixture/raced-serve-state.json"
  export SKIDBLADNIR_TEST_LOCALAPI_RACE_STATE="$fixture/raced-serve-state.json"
  export SKIDBLADNIR_TEST_LOCALAPI_RACE_ONCE="$fixture/localapi-race-once"
  : >"$SKIDBLADNIR_TEST_CALLS"
  set +e
  (skidbladnir_configure_serve "$test_bin/tailscale" arch) \
    >"$fixture/raced-serve-output" 2>"$fixture/raced-serve-error"
  local raced_serve_result=$?
  set -e
  unset SKIDBLADNIR_TEST_LOCALAPI_RACE_STATE SKIDBLADNIR_TEST_LOCALAPI_RACE_ONCE
  [[ "$raced_serve_result" -ne 0 ]] || fail 'concurrent Serve change did not defeat compare-and-swap'
  jq -e --argjson raced "$raced_serve_status" '. == $raced' "$serve_state" >/dev/null ||
    fail 'failed compare-and-swap erased the concurrent Serve change'
  ! grep -Fq 'tailscale serve --bg' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'concurrent Serve change was followed by CLI mutation'

  local shared_serve_status='{"TCP":{"8443":{"HTTPS":true},"9443":{"HTTPS":true}},"Web":{"current.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}},"other.example.ts.net:9443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:9000"}}}}}'
  printf '%s\n' "$shared_serve_status" >"$serve_state"
  : >"$SKIDBLADNIR_TEST_CALLS"
  skidbladnir_configure_serve "$test_bin/tailscale" arch
  ! grep -Fq 'curl-localapi' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'single canonical mapping entered duplicate reconciliation'
  jq -e '
    .TCP["9443"] == {HTTPS:true} and
    .Web["other.example.ts.net:9443"] == {Handlers:{"/":{Proxy:"http://127.0.0.1:9000"}}}
  ' "$serve_state" >/dev/null || fail 'ordinary convergence changed unrelated Serve state'
  [[ -z "$(find "$serve_tmp" -mindepth 1 -print -quit)" ]] ||
    fail 'duplicate Serve repair left temporary files after a failure path'
  unset SKIDBLADNIR_TEST_SERVE_STATE SKIDBLADNIR_TEST_SERVE_ETAG \
    SKIDBLADNIR_TEST_SERVE_HOST SKIDBLADNIR_TEST_TAILSCALE_SOCKET \
    SKIDBLADNIR_TEST_LOCALAPI_PORT SKIDBLADNIR_TEST_LOCALAPI_TOKEN TMPDIR

  local doctor_output="$fixture/doctor-output"
  doctor_reset
  skidbladnir_doctor arch >"$doctor_output"
  assert_eq 9 "$(grep -Ec '^PASS  skidbladnir[.]' "$doctor_output")" 'healthy doctor PASS fact count'
  assert_contains "$doctor_output" 'skidbladnir.artifact.version'
  assert_contains "$doctor_output" 'v1.2.3 at source 1111111111111111111111111111111111111111'
  assert_contains "$doctor_output" 'skidbladnir.artifact.digest'
  assert_contains "$doctor_output" 'pinned archive and all installed release members match'
  assert_contains "$doctor_output" 'skidbladnir.config'
  assert_contains "$doctor_output" 'strict arch host config, hooks, Claude plugin, and notifier installed'
  assert_contains "$doctor_output" 'skidbladnir.secrets'
  assert_contains "$doctor_output" 'machine handle and bearer are canonical mode-0600 files'
  assert_contains "$doctor_output" 'skidbladnir.service'
  assert_contains "$doctor_output" 'systemd user definition matches and is enabled and active'
  assert_contains "$doctor_output" 'skidbladnir.loopback'
  assert_contains "$doctor_output" 'authenticated tmux-free loopback pressure endpoint is healthy'
  assert_contains "$doctor_output" 'skidbladnir.serve'
  assert_contains "$doctor_output" 'private HTTPS 8443 exposes only loopback /v1'
  assert_contains "$doctor_output" 'skidbladnir.tmux'
  assert_contains "$doctor_output" 'tmux 3.7c matches the last tested version'
  assert_contains "$doctor_output" 'skidbladnir.tailscale'
  assert_contains "$doctor_output" 'Tailscale is signed in'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-config url\ =\ \"http://127.0.0.1:7341/v1/pressure\"'
  [[ ! -e "$SKIDBLADNIR_TEST_CURL_LEAK" ]] || fail 'credential-bearing curl honored ambient config or proxy state'
  ! grep -Fq '/v1/sessions' "$SKIDBLADNIR_TEST_CALLS" || fail 'doctor reached the normalizing inventory endpoint'
  bearer="$bearer_before"
  arch_token="" devbox_token="" local_token=""
  assert_no_secret "$doctor_output"
  local xtrace_output="$fixture/doctor-xtrace"
  local doctor_status_marker=doctor-status-only-private-marker
  export SKIDBLADNIR_TEST_TAILSCALE_STATUS="{\"BackendState\":\"Running\",\"Self\":{\"DNSName\":\"current.example.ts.net.\"},\"Peer\":{\"$doctor_status_marker\":{\"UserID\":12345}}}"
  {
    set -x
    doctor_reset
    skidbladnir_doctor arch >/dev/null
    set +x
  } 2>"$xtrace_output"
  unset SKIDBLADNIR_TEST_TAILSCALE_STATUS
  assert_no_secret "$xtrace_output"
  for private_value in "$doctor_status_marker" current.example.ts.net; do
    ! grep -Fq "$private_value" "$xtrace_output" ||
      fail 'doctor exposed private Tailscale status under xtrace'
  done

  local tmux_drift_output="$fixture/doctor-tmux-drift-output"
  export SKIDBLADNIR_TEST_TMUX_VERSION='tmux 3.8'
  if ! skidbladnir_require_tmux_runtime arch; then
    fail 'tmux version drift blocked runtime convergence'
  fi
  doctor_reset
  skidbladnir_doctor arch >"$tmux_drift_output"
  assert_eq 0 "$doctor_failures" 'tmux drift doctor failure count'
  assert_eq 1 "$doctor_warnings" 'tmux drift doctor warning count'
  assert_contains "$tmux_drift_output" 'WARN  skidbladnir.tmux'
  assert_contains "$tmux_drift_output" 'tmux 3.8 installed; last tested with tmux 3.7c'
  doctor_summary >"$fixture/doctor-tmux-drift-summary" 2>&1 ||
    fail 'advisory tmux drift made doctor fail'
  assert_contains "$fixture/doctor-tmux-drift-summary" 'doctor: warn (1 warning(s))'
  unset SKIDBLADNIR_TEST_TMUX_VERSION

  printf '\n# locally replaced after convergence\n' >>"$test_home/.local/bin/skidbladnir"
  skidbladnir_sha256 "$test_home/.local/bin/skidbladnir" \
    >"$test_home/.local/share/skidbladnir/binary.sha256"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/self-resealed-artifact-output" || true
  assert_contains "$fixture/self-resealed-artifact-output" \
    'FAIL  skidbladnir.artifact.digest'
  install -m 0755 "$fixture/release/skidbladnir" \
    "$test_home/.local/bin/skidbladnir"
  skidbladnir_sha256 "$test_home/.local/bin/skidbladnir" \
    >"$test_home/.local/share/skidbladnir/binary.sha256"

  export SKIDBLADNIR_TEST_INVENTORY
  SKIDBLADNIR_TEST_INVENTORY='{"machine":{"handle":"mh-11111111111111111111111111111111"},"observedAt":"first","sessions":[{"tmuxId":"$2","tmuxName":"second","identityToken":"v1-22222222222222222222222222222222.20.30.2","objective":"private two"},{"tmuxId":"$0","tmuxName":"first","identityToken":"v1-11111111111111111111111111111111.20.30.1","objective":"private one"}]}'
  local lifetime_before lifetime_after
  lifetime_before="$(skidbladnir_reconciled_lifetime_digest_local)"
  SKIDBLADNIR_TEST_INVENTORY='{"machine":{"handle":"mh-11111111111111111111111111111111"},"observedAt":"later","sessions":[{"tmuxId":"$0","tmuxName":"first","identityToken":"v1-11111111111111111111111111111111.20.30.1","objective":"changed"},{"tmuxId":"$2","tmuxName":"second","identityToken":"v1-22222222222222222222222222222222.20.30.2","attention":true}]}'
  lifetime_after="$(skidbladnir_reconciled_lifetime_digest_local)"
  assert_eq "$lifetime_before" "$lifetime_after" 'lifetime digest ignores inventory order and mutable card facts'
  [[ "$lifetime_before" =~ ^[0-9a-f]{64}$ ]] || fail 'lifetime digest is not one lowercase SHA-256'
  SKIDBLADNIR_TEST_INVENTORY='{"machine":{"handle":"mh-11111111111111111111111111111111"},"sessions":[{"id":"$0","tmuxName":"first","identityToken":"v1-11111111111111111111111111111111.20.30.1"}]}'
  if skidbladnir_reconciled_lifetime_digest_local >/dev/null 2>&1; then
    fail 'lifetime digest accepted the retired session id field'
  fi
  unset SKIDBLADNIR_TEST_INVENTORY

  printf 'catalogue drift\n' >>"$test_home/.local/share/skidbladnir/characters.json"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/catalogue-drift-output" || true
  assert_contains "$fixture/catalogue-drift-output" 'FAIL  skidbladnir.artifact.digest'
  cp "$fixture/release/characters.json" "$test_home/.local/share/skidbladnir/characters.json"

  printf '\n# service drift\n' >>"$test_home/.config/systemd/user/skidbladnir.service"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/service-drift-output" || true
  assert_contains "$fixture/service-drift-output" 'FAIL  skidbladnir.service'
  cp "$repo_dir/assets/skidbladnir/skidbladnir.service" "$test_home/.config/systemd/user/skidbladnir.service"

  export SKIDBLADNIR_TEST_SERVE_STATUS='{"TCP":{"8443":{"HTTPS":true}},"Web":{"host.example.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:7341"}}}}}'
  doctor_reset
  skidbladnir_doctor arch >"$fixture/root-serve-output" || true
  assert_contains "$fixture/root-serve-output" 'FAIL  skidbladnir.serve'
  unset SKIDBLADNIR_TEST_SERVE_STATUS

  export SKIDBLADNIR_TEST_SERVE_STATUS='{"TCP":{"8443":{"HTTPS":true}},"Web":{"host.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":{"host.example.ts.net:8443":true}}'
  doctor_reset
  skidbladnir_doctor arch >"$fixture/funnel-serve-output" || true
  assert_contains "$fixture/funnel-serve-output" 'FAIL  skidbladnir.serve'
  assert_contains "$fixture/funnel-serve-output" \
    'public Funnel is enabled on HTTPS 8443; run tailscale funnel --https=8443 off, then converge again'
  ! grep -Fq 'dedicated Serve mapping missing' "$fixture/funnel-serve-output" ||
    fail 'Funnel doctor prescribed a convergence-only recovery loop'
  unset SKIDBLADNIR_TEST_SERVE_STATUS

  printf '\n' >>"$test_home/.config/skidbladnir/host-config.json"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/drift-output" || true
  assert_contains "$fixture/drift-output" 'FAIL  skidbladnir.config'
  assert_contains "$fixture/drift-output" 'owned host config, hooks, Claude plugin, or notifier differs; run the platform converge command'
  cp "$fixture/host-config.json" "$test_home/.config/skidbladnir/host-config.json"
  chmod 0600 "$test_home/.config/skidbladnir/host-config.json"

  printf '\n' >>"$test_home/.codex-work/hooks.json"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/hooks-drift-output" || true
  assert_contains "$fixture/hooks-drift-output" 'FAIL  skidbladnir.config'
  cp "$(skidbladnir_agent_hooks_source arch)" "$test_home/.codex-work/hooks.json"
  chmod 0600 "$test_home/.codex-work/hooks.json"

  printf '\n' >>"$installed_plugin/hooks/hooks.json"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/plugin-drift-output" || true
  assert_contains "$fixture/plugin-drift-output" 'FAIL  skidbladnir.config'
  install -m 0644 \
    "$repo_dir/assets/skidbladnir/claude-agent-identity/hooks/hooks.json" \
    "$installed_plugin/hooks/hooks.json"

  chmod 0644 "$installed_plugin/bin/agent-hook"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/plugin-mode-output" || true
  assert_contains "$fixture/plugin-mode-output" 'FAIL  skidbladnir.config'
  chmod 0755 "$installed_plugin/bin/agent-hook"

  mv "$installed_plugin/bin" "$installed_plugin/bin.real"
  ln -s bin.real "$installed_plugin/bin"
  if (skidbladnir_preflight_owned_directories "$test_home") >/dev/null 2>&1; then
    fail 'Claude plugin directory symlink passed deployment preflight'
  fi
  doctor_reset
  skidbladnir_doctor arch >"$fixture/plugin-symlink-output" || true
  assert_contains "$fixture/plugin-symlink-output" 'FAIL  skidbladnir.config'
  /bin/unlink "$installed_plugin/bin"
  mv "$installed_plugin/bin.real" "$installed_plugin/bin"

  chmod 0644 "$test_home/.config/skidbladnir/bearer"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/secret-drift-output" || true
  assert_contains "$fixture/secret-drift-output" 'FAIL  skidbladnir.secrets'
  assert_contains "$fixture/secret-drift-output" 'credential files are absent, malformed, or not mode 0600'
  assert_contains "$fixture/secret-drift-output" 'FAIL  skidbladnir.loopback'
  assert_no_secret "$fixture/secret-drift-output"
  chmod 0600 "$test_home/.config/skidbladnir/bearer"

  local mac_agent_dir="$test_home/Library/LaunchAgents"
  install -d -m 0755 "$mac_agent_dir"
  install -m 0644 "$repo_dir/assets/skidbladnir/dev.niels.skidbladnir.plist" \
    "$mac_agent_dir/dev.niels.skidbladnir.plist"
  launchctl() {
    printf 'launchctl' >>"$SKIDBLADNIR_TEST_CALLS"
    printf ' %q' "$@" >>"$SKIDBLADNIR_TEST_CALLS"
    printf '\n' >>"$SKIDBLADNIR_TEST_CALLS"
    if [[ "${1:-}" == print ]]; then
      printf 'state = running\n'
      return 0
    fi
  }
  id() {
    [[ "${1:-}" == -u && $# -eq 1 ]] || return 64
    printf '501\n'
  }
  : >"$SKIDBLADNIR_TEST_CALLS"
  # shellcheck disable=SC2034
  skidbladnir_changed=0
  skidbladnir_activate_macos_service "$test_home"
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'launchctl kickstart gui/501/dev.niels.skidbladnir'
  ! grep -Fq 'launchctl bootout' "$SKIDBLADNIR_TEST_CALLS" || fail 'unchanged loaded LaunchAgent was restarted'

  : >"$SKIDBLADNIR_TEST_CALLS"
  # shellcheck disable=SC2034
  skidbladnir_changed=0
  skidbladnir_mark_release_activation_required macos "$test_home" \
    v1.2.3 1111111111111111111111111111111111111111
  skidbladnir_resume_release_activation macos "$test_home"
  assert_eq 1 "$skidbladnir_changed" \
    'persisted release activation state did not restore changed intent on macOS'
  skidbladnir_activate_macos_service "$test_home"
  skidbladnir_clear_release_activation macos "$test_home"
  local expected_launchctl="$fixture/changed-launchctl-calls"
  printf '%s\n' \
    'launchctl print gui/501/dev.niels.skidbladnir' \
    'launchctl enable gui/501/dev.niels.skidbladnir' \
    "launchctl bootout gui/501 $mac_agent_dir/dev.niels.skidbladnir.plist" \
    "launchctl bootstrap gui/501 $mac_agent_dir/dev.niels.skidbladnir.plist" \
    >"$expected_launchctl"
  cmp -s "$expected_launchctl" "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'changed LaunchAgent did not reload once in path-owned order'
  unset -f launchctl id

  local -a journaled_targets=(
    "$test_home/.local/bin/skidbladnir-launch"
    "$test_home/.config/systemd/user/skidbladnir.service"
    "$test_home/.local/bin/skidbladnir"
    "$test_home/.local/share/skidbladnir/characters.json"
    "$test_home/.local/share/skidbladnir/release.json"
    "$test_home/.local/share/skidbladnir/release-bundle.tar.gz"
    "$test_home/.config/skidbladnir/host-config.json"
    "$test_home/.local/bin/skid-notify"
    "$test_home/.codex-personal/hooks.json"
    "$test_home/.codex-work/hooks.json"
    "$test_home/.codex-work2/hooks.json"
    "$test_home/.local/share/skidbladnir/claude-agent-identity/.claude-plugin/plugin.json"
    "$test_home/.local/share/skidbladnir/claude-agent-identity/hooks/hooks.json"
    "$test_home/.local/share/skidbladnir/claude-agent-identity/bin/agent-hook"
  )
  local journaled_before
  journaled_before="$(deployment_owned_snapshot "${journaled_targets[@]}")"
  local old_binary_sha old_catalogue_sha old_manifest_sha old_bundle_sha
  old_binary_sha="$(skidbladnir_sha256 "$test_home/.local/bin/skidbladnir")"
  old_catalogue_sha="$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/characters.json")"
  old_manifest_sha="$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/release.json")"
  old_bundle_sha="$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/release-bundle.tar.gz")"
  sed -e 's/v1[.]2[.]3/v1.2.4/g' \
    -e 's/1111111111111111111111111111111111111111/2222222222222222222222222222222222222222/g' \
    "$fixture/release/skidbladnir" >"$fixture/release/skidbladnir.next"
  mv "$fixture/release/skidbladnir.next" "$fixture/release/skidbladnir"
  chmod 0755 "$fixture/release/skidbladnir"
  printf '{"release":2}\n' >"$fixture/release/characters.json"
  jq '.version = "v1.2.4" | .sourceSha = "2222222222222222222222222222222222222222"' \
    "$fixture/release/release.json" >"$fixture/release/release.next.json"
  mv "$fixture/release/release.next.json" "$fixture/release/release.json"
  tar -czf "$fixture/skidbladnir-linux-amd64.tar.gz" -C "$fixture/release" \
    skidbladnir characters.json release.json
  local next_archive_sha
  next_archive_sha="$(skidbladnir_sha256 "$fixture/skidbladnir-linux-amd64.tar.gz")"
  jq --arg digest "$next_archive_sha" \
    '.version = "v1.2.4" | .sourceSha = "2222222222222222222222222222222222222222" |
      .androidApkSha256 = $digest | .androidSigningCertAssetSha256 = $digest |
      .linuxAmd64Sha256 = $digest | .darwinArm64Sha256 = $digest |
      .sha256SumsAssetSha256 = $digest' \
    "$skidbladnir_release_pin_file" >"$fixture/release-pin.next.json"
  mv "$fixture/release-pin.next.json" "$skidbladnir_release_pin_file"
  jq '.profiles[0].label = "Codex · Personal Next"' \
    "$fixture/host-config.json" >"$fixture/host-config.next.json"
  mv "$fixture/host-config.next.json" "$fixture/host-config.json"
  [[ "$(skidbladnir_sha256 "$fixture/release/skidbladnir")" != "$old_binary_sha" ]] ||
    fail 'next release binary fixture is not byte-distinct'
  ! cmp -s "$fixture/host-config.json" "$test_home/.config/skidbladnir/host-config.json" ||
    fail 'next host config fixture is not byte-distinct'
  : >"$SKIDBLADNIR_TEST_CALLS"
  export SKIDBLADNIR_TEST_FAIL_INSTALL_TARGET='.host-config.json.skidbladnir.'
  export SKIDBLADNIR_TEST_FAIL_INSTALL_ONCE="$fixture/install-failed-once"
  set +e
  skidbladnir_converge arch >/dev/null 2>"$fixture/release-transaction-error"
  local transaction_status=$?
  set -e
  unset SKIDBLADNIR_TEST_FAIL_INSTALL_TARGET SKIDBLADNIR_TEST_FAIL_INSTALL_ONCE
  [[ "$transaction_status" -ne 0 ]] || fail 'injected release promotion failure unexpectedly succeeded'
  [[ -f "$fixture/install-failed-once" ]] ||
    fail 'host-config install failure injection did not reach its target'
  assert_contains "$fixture/release-transaction-error" \
    'Could not stage Skidbladnir owned target:'
  assert_eq "$old_binary_sha" "$(skidbladnir_sha256 "$test_home/.local/bin/skidbladnir")" \
    'failed release transaction preserved binary'
  assert_eq "$old_catalogue_sha" "$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/characters.json")" \
    'failed release transaction preserved catalogue'
  assert_eq "$old_manifest_sha" "$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/release.json")" \
    'failed release transaction preserved manifest'
  assert_eq "$old_bundle_sha" "$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/release-bundle.tar.gz")" \
    'failed release transaction preserved retained bundle'
  assert_eq "$journaled_before" "$(deployment_owned_snapshot "${journaled_targets[@]}")" \
    'failed release transaction restored every deployment-owned file byte and mode'
  assert_eq "$handle_before" "$(cat "$test_home/.config/skidbladnir/machine-handle")" \
    'failed release transaction preserved machine handle'
  assert_eq "$bearer_before" "$(cat "$test_home/.config/skidbladnir/bearer")" \
    'failed release transaction preserved bearer'
  ! grep -Eq '^(systemctl|tailscale)' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'failed local file transaction reached service or Serve convergence'

  skidbladnir_begin_release_transaction arch "$test_home"
  skidbladnir_install_owned "$fixture/release/skidbladnir" "$test_home/.local/bin/skidbladnir" 0755
  set +e
  HOME="$test_home" "$test_home/.local/bin/skidbladnir-launch" version \
    >"$fixture/incomplete-launch-output" 2>"$fixture/incomplete-launch-error"
  local incomplete_launch_status=$?
  set -e
  assert_eq 75 "$incomplete_launch_status" 'incomplete release transaction blocks service launch'
  [[ ! -s "$fixture/incomplete-launch-output" ]] || fail 'incomplete release transaction launcher wrote stdout'
  assert_contains "$fixture/incomplete-launch-error" \
    'Skidbladnir release installation is incomplete; run the platform converge command'
  skidbladnir_recover_release_transaction arch "$test_home"
  assert_eq "$old_binary_sha" "$(skidbladnir_sha256 "$test_home/.local/bin/skidbladnir")" \
    'crash recovery restored binary'
  [[ ! -e "$test_home/.local/share/skidbladnir/.release-transaction" ]] ||
    fail 'crash recovery left its release transaction journal'

  skidbladnir_begin_release_transaction arch "$test_home"
  skidbladnir_install_owned "$fixture/release/skidbladnir" "$test_home/.local/bin/skidbladnir" 0755
  cp "$skidbladnir_release_pin_file" "$fixture/release-pin.before-pending.json"
  jq 'map_values("PENDING")' "$skidbladnir_release_pin_file" >"$fixture/release-pin.pending.json"
  mv "$fixture/release-pin.pending.json" "$skidbladnir_release_pin_file"
  set +e
  skidbladnir_converge arch >/dev/null 2>"$fixture/pending-pin-recovery-error"
  local pending_pin_recovery_status=$?
  set -e
  mv "$fixture/release-pin.before-pending.json" "$skidbladnir_release_pin_file"
  [[ "$pending_pin_recovery_status" -ne 0 ]] ||
    fail 'pending release pin unexpectedly permitted convergence'
  assert_contains "$fixture/pending-pin-recovery-error" 'Skidbladnir release pin is pending'
  [[ ! -e "$test_home/.local/share/skidbladnir/.release-transaction" ]] ||
    fail 'pending release pin stranded the prior release transaction journal'
  assert_eq "$old_binary_sha" "$(skidbladnir_sha256 "$test_home/.local/bin/skidbladnir")" \
    'pending release pin recovered the prior binary before failing closed'

  : >"$SKIDBLADNIR_TEST_CALLS"
  export SKIDBLADNIR_TEST_FAIL_RESTART_ONCE="$fixture/service-restart-failed-once"
  set +e
  skidbladnir_converge arch >/dev/null 2>"$fixture/service-activation-error"
  local activation_status=$?
  set -e
  unset SKIDBLADNIR_TEST_FAIL_RESTART_ONCE
  [[ "$activation_status" -ne 0 ]] || fail 'injected service activation failure unexpectedly succeeded'
  [[ -f "$fixture/service-restart-failed-once" ]] ||
    fail 'service restart failure injection did not reach its target'
  assert_eq 'v1.2.4 2222222222222222222222222222222222222222' \
    "$("$test_home/.local/bin/skidbladnir" version)" \
    'failed service activation did not retain the committed release'
  assert_eq 'v1.2.3 1111111111111111111111111111111111111111' \
    "$(cat "$SKIDBLADNIR_TEST_SERVICE_VERSION")" \
    'failed service activation changed the running release'
  local activation_marker
  activation_marker="$(skidbladnir_release_activation_marker arch "$test_home")"
  [[ -f "$activation_marker" && ! -L "$activation_marker" ]] ||
    fail 'failed service activation did not leave a regular retry marker'
  assert_eq 600 "$(skidbladnir_file_mode "$activation_marker")" \
    'release activation retry marker mode'
  assert_eq $'arch\tv1.2.4\t2222222222222222222222222222222222222222' \
    "$(cat "$activation_marker")" \
    'release activation retry marker target'
  [[ ! -e "$test_home/.local/share/skidbladnir/.release-transaction" ]] ||
    fail 'failed service activation left an artifact transaction journal'
  ! grep -Fq 'tailscale ' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'failed service activation reached Serve convergence'
  doctor_reset
  skidbladnir_doctor arch >"$fixture/pending-activation-doctor" || true
  assert_contains "$fixture/pending-activation-doctor" 'FAIL  skidbladnir.service'

  : >"$SKIDBLADNIR_TEST_CALLS"
  export SKIDBLADNIR_TEST_IS_ACTIVE_UNAVAILABLE=1
  skidbladnir_converge arch
  unset SKIDBLADNIR_TEST_IS_ACTIVE_UNAVAILABLE
  assert_eq 'v1.2.4 2222222222222222222222222222222222222222' \
    "$(cat "$SKIDBLADNIR_TEST_SERVICE_VERSION")" \
    'retry after service activation failure left the prior release running'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'systemctl --user restart skidbladnir.service'
  [[ ! -e "$activation_marker" && ! -L "$activation_marker" ]] ||
    fail 'successful service activation retained its retry marker'
  doctor_reset
  skidbladnir_doctor arch >"$fixture/retried-activation-doctor"
  assert_contains "$fixture/retried-activation-doctor" 'PASS  skidbladnir.service'

  : >"$SKIDBLADNIR_TEST_CALLS"
  skidbladnir_converge arch
  ! grep -Fq 'systemctl --user restart skidbladnir.service' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'healthy unchanged Linux service was restarted after activation recovery'

  /bin/unlink "$test_home/.codex-personal/config.toml"
  : >"$SKIDBLADNIR_TEST_CALLS"
  skidbladnir_converge arch
  assert_contains "$test_home/.codex-personal/config.toml" \
    "notify = [\"$test_home/.local/bin/skid-notify\"]"
  ! grep -Fq 'systemctl --user restart skidbladnir.service' "$SKIDBLADNIR_TEST_CALLS" ||
    fail 'Codex notify-only convergence restarted the unchanged gateway service'

  assert_invalid_activation_marker() {
    local label="$1"
    local status
    doctor_reset
    skidbladnir_doctor arch >"$fixture/invalid-marker-$label-doctor" || true
    ! grep -Fq 'PASS  skidbladnir.service' "$fixture/invalid-marker-$label-doctor" ||
      fail "$label activation marker let doctor report a healthy service"
    : >"$SKIDBLADNIR_TEST_CALLS"
    set +e
    skidbladnir_converge arch >/dev/null 2>"$fixture/invalid-marker-$label-error"
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || fail "$label activation marker permitted convergence"
    ! grep -Eq '^(systemctl|tailscale)' "$SKIDBLADNIR_TEST_CALLS" ||
      fail "$label activation marker reached a service boundary"
    [[ ! -e "$test_home/.local/share/skidbladnir/.release-transaction" ]] ||
      fail "$label activation marker stranded a release transaction"
  }

  local marker_referent="$fixture/activation-marker-referent"
  printf 'preserve me\n' >"$marker_referent"
  ln -s "$marker_referent" "$activation_marker"
  assert_invalid_activation_marker symlink
  assert_eq 'preserve me' "$(cat "$marker_referent")" \
    'invalid activation-marker symlink changed its referent'
  /bin/unlink "$activation_marker"

  ln -s "$fixture/missing-activation-marker-referent" "$activation_marker"
  assert_invalid_activation_marker broken-symlink
  [[ ! -e "$fixture/missing-activation-marker-referent" ]] ||
    fail 'broken activation-marker symlink created its missing referent'
  /bin/unlink "$activation_marker"

  printf '%s\n' $'arch\tv1.2.4\t2222222222222222222222222222222222222222' \
    >"$activation_marker"
  chmod 0644 "$activation_marker"
  assert_invalid_activation_marker mode
  /bin/unlink "$activation_marker"

  printf 'malformed\n' >"$activation_marker"
  chmod 0600 "$activation_marker"
  assert_invalid_activation_marker malformed
  /bin/unlink "$activation_marker"

  printf '%s\ntrailing\n' $'arch\tv1.2.4\t2222222222222222222222222222222222222222' \
    >"$activation_marker"
  chmod 0600 "$activation_marker"
  assert_invalid_activation_marker trailing-data
  /bin/unlink "$activation_marker"
  unset -f assert_invalid_activation_marker
  PATH="$old_path"
  export PATH
  pass
}

write_invite_boundaries() {
  local invite_expiry
  case "$(uname -s)" in
  Darwin) invite_expiry="$(date -u -v+4M '+%Y-%m-%dT%H:%M:%SZ')" ;;
  *) invite_expiry="$(date -u -d '+4 minutes' '+%Y-%m-%dT%H:%M:%SZ')" ;;
  esac
  arch_token=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
  devbox_token=BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBg
  local_token=CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCw
  bearer=DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD
  arch_response="$(jq -cn --arg token "$arch_token" --arg expiry "$invite_expiry" '{pairingInviteToken:$token,expiresAt:$expiry,machine:{handle:"mh-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",platform:"Linux"}}')"
  devbox_response="$(jq -cn --arg token "$devbox_token" --arg expiry "$invite_expiry" '{pairingInviteToken:$token,expiresAt:$expiry,machine:{handle:"mh-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",platform:"Linux"}}')"
  local_response="$(jq -cn --arg token "$local_token" --arg expiry "$invite_expiry" '{pairingInviteToken:$token,expiresAt:$expiry,machine:{handle:"mh-cccccccccccccccccccccccccccccccc",platform:"Darwin"}}')"
  export arch_response devbox_response local_response

  cat >"$fixture/invite-local" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
touch "$SKIDBLADNIR_INVITE_STARTS/Local"
for _attempt in {1..100}; do
  [[ -e "$SKIDBLADNIR_INVITE_STARTS/Arch" && -e "$SKIDBLADNIR_INVITE_STARTS/DevServer" ]] && break
  sleep 0.01
done
[[ -e "$SKIDBLADNIR_INVITE_STARTS/Arch" && -e "$SKIDBLADNIR_INVITE_STARTS/DevServer" ]]
line=local
for field in "$@"; do printf -v line '%s %q' "$line" "$field"; done
printf '%s\n' "$line" >> "$SKIDBLADNIR_INVITE_CALLS"
printf '%s\n' "$local_response"
EOF
  chmod 0755 "$fixture/invite-local"
  jq -n '{Arch:"https://arch.example-tailnet.ts.net:8443/",DevServer:"https://dev-server.example-tailnet.ts.net:8443/",Local:"https://macbook.example-tailnet.ts.net:8443/"}' \
    >"$fixture/origins.json"
  chmod 0600 "$fixture/origins.json"
}

test_invite_success_and_fail_closed() {
  write_invite_boundaries
  # shellcheck source=lib/skidbladnir-invite.sh
  source "$repo_dir/lib/skidbladnir-invite.sh"
  export SKIDBLADNIR_INVITE_CALLS="$fixture/invite-calls"
  export SKIDBLADNIR_INVITE_QR="$fixture/invite-qr"
  export SKIDBLADNIR_INVITE_STARTS="$fixture/invite-starts"
  install -d -m 0700 "$SKIDBLADNIR_INVITE_STARTS"

  local far_expiry duplicate_response far_response
  case "$(uname -s)" in
  Darwin) far_expiry="$(date -u -v+1H '+%Y-%m-%dT%H:%M:%SZ')" ;;
  *) far_expiry="$(date -u -d '+1 hour' '+%Y-%m-%dT%H:%M:%SZ')" ;;
  esac
  duplicate_response="${arch_response/\"expiresAt\"/\"pairingInviteToken\":\"$arch_token\",\"expiresAt\"}"
  if skidbladnir_invite_response_valid "$duplicate_response" Linux; then
    fail 'fleet invite accepted a duplicate response member'
  fi
  far_response="$(jq -cn --arg token "$arch_token" --arg expiry "$far_expiry" \
    '{pairingInviteToken:$token,expiresAt:$expiry,machine:{handle:"mh-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",platform:"Linux"}}')"
  if skidbladnir_invite_response_valid "$far_response" Linux; then
    fail 'fleet invite accepted an expiry beyond five minutes'
  fi

  ssh() {
    local target
    case " $* " in
    *' nnandal@arch '*) target=Arch ;;
    *' dev-server '*) target=DevServer ;;
    *) return 64 ;;
    esac
    touch "$SKIDBLADNIR_INVITE_STARTS/$target"
    for _attempt in {1..100}; do
      [[ -e "$SKIDBLADNIR_INVITE_STARTS/Arch" && -e "$SKIDBLADNIR_INVITE_STARTS/DevServer" && -e "$SKIDBLADNIR_INVITE_STARTS/Local" ]] && break
      sleep 0.01
    done
    [[ -e "$SKIDBLADNIR_INVITE_STARTS/Arch" && -e "$SKIDBLADNIR_INVITE_STARTS/DevServer" && -e "$SKIDBLADNIR_INVITE_STARTS/Local" ]]
    local line=ssh field
    for field in "$@"; do printf -v line '%s %q' "$line" "$field"; done
    printf '%s\n' "$line" >>"$SKIDBLADNIR_INVITE_CALLS"
    case " $* " in
    *' nnandal@arch '*)
      [[ "${SKIDBLADNIR_FAIL_ARCH:-0}" == 0 ]] || return 9
      if [[ "${SKIDBLADNIR_SWAP_ORIGINS:-0}" == 1 ]]; then
        jq -n \
          '{Arch:"https://replaced-arch.example-tailnet.ts.net:8443/",DevServer:"https://replaced-devbox.example-tailnet.ts.net:8443/",Local:"https://replaced-macbook.example-tailnet.ts.net:8443/"}' \
          >"$fixture/origins.replacement.json"
        chmod 0600 "$fixture/origins.replacement.json"
        mv "$fixture/origins.replacement.json" "$fixture/origins.json"
      fi
      printf '%s\n' "$arch_response"
      ;;
    *' dev-server '*) printf '%s\n' "$devbox_response" ;;
    *) return 64 ;;
    esac
  }
  qrencode() {
    printf 'qrencode' >>"$SKIDBLADNIR_INVITE_CALLS"
    printf ' %q' "$@" >>"$SKIDBLADNIR_INVITE_CALLS"
    printf '\n' >>"$SKIDBLADNIR_INVITE_CALLS"
    cat >"$SKIDBLADNIR_INVITE_QR"
    printf 'QR\n'
  }

  : >"$SKIDBLADNIR_INVITE_CALLS"
  rm -f -- "$SKIDBLADNIR_INVITE_STARTS"/*
  skidbladnir_invite "$fixture/origins.json" "$fixture/invite-local" >"$fixture/invite-output"
  assert_eq 4 "$(wc -l <"$SKIDBLADNIR_INVITE_CALLS" | tr -d '[:space:]')" 'three host calls and one QR call'
  assert_contains "$SKIDBLADNIR_INVITE_CALLS" 'ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 nnandal@arch'
  assert_contains "$SKIDBLADNIR_INVITE_CALLS" 'ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 dev-server'
  assert_contains "$SKIDBLADNIR_INVITE_CALLS" 'local pairing-invite create'
  assert_contains "$SKIDBLADNIR_INVITE_CALLS" 'qrencode -t ANSIUTF8'
  assert_eq 'Fleet invite ready. It expires in 5 minutes and works once. On the phone, open Skíðblaðnir and tap Connect.' \
    "$(sed -n '1p' "$fixture/invite-output")" 'frozen invite instruction'
  assert_no_secret "$fixture/invite-output"
  assert_no_secret "$SKIDBLADNIR_INVITE_CALLS"
  jq -e --arg arch "$arch_token" --arg devbox "$devbox_token" --arg local "$local_token" '
    type == "object" and keys == ["kind", "machines"] and .kind == "skidbladnir.fleet-invite.v1" and
    (.machines | map(.label)) == ["Arch", "Devbox", "MacBook"] and
    (.machines | map(.pairingInviteToken)) == [$arch, $devbox, $local] and
    (.machines | map(.machineHandle) | unique | length) == 3 and
    (.machines | map(.origin) | unique | length) == 3
  ' "$SKIDBLADNIR_INVITE_QR" >/dev/null || fail 'QR payload differs from the strict fixed fleet'
  (($(LC_ALL=C wc -c <"$SKIDBLADNIR_INVITE_QR") <= 4096)) || fail 'QR payload exceeds 4096 bytes'

  : >"$SKIDBLADNIR_INVITE_CALLS"
  rm -f -- "$SKIDBLADNIR_INVITE_STARTS"/* "$SKIDBLADNIR_INVITE_QR"
  export SKIDBLADNIR_SWAP_ORIGINS=1
  skidbladnir_invite "$fixture/origins.json" "$fixture/invite-local" \
    >"$fixture/invite-snapshot-output"
  unset SKIDBLADNIR_SWAP_ORIGINS
  jq -e '
    (.machines | map(.origin)) == [
      "https://arch.example-tailnet.ts.net:8443/",
      "https://dev-server.example-tailnet.ts.net:8443/",
      "https://macbook.example-tailnet.ts.net:8443/"
    ]
  ' "$SKIDBLADNIR_INVITE_QR" >/dev/null ||
    fail 'fleet invite did not retain the validated origins snapshot'
  jq -n '{Arch:"https://arch.example-tailnet.ts.net:8443/",DevServer:"https://dev-server.example-tailnet.ts.net:8443/",Local:"https://macbook.example-tailnet.ts.net:8443/"}' \
    >"$fixture/origins.json"
  chmod 0600 "$fixture/origins.json"

  : >"$SKIDBLADNIR_INVITE_CALLS"
  rm -f -- "$SKIDBLADNIR_INVITE_STARTS"/*
  rm -f -- "$SKIDBLADNIR_INVITE_QR"
  export SKIDBLADNIR_FAIL_ARCH=1
  set +e
  (skidbladnir_invite "$fixture/origins.json" "$fixture/invite-local") >"$fixture/invite-fail-output" 2>"$fixture/invite-fail-error"
  status=$?
  set -e
  unset SKIDBLADNIR_FAIL_ARCH
  [[ "$status" -ne 0 ]] || fail 'partial invitation unexpectedly succeeded'
  assert_eq 3 "$(wc -l <"$SKIDBLADNIR_INVITE_CALLS" | tr -d '[:space:]')" 'failure still requests all three hosts'
  [[ ! -e "$SKIDBLADNIR_INVITE_QR" ]] || fail 'partial invitation reached QR boundary'
  [[ ! -s "$fixture/invite-fail-output" ]] || fail 'partial invitation wrote stdout'
  assert_contains "$fixture/invite-fail-error" "Couldn't create the whole fleet invite. Nothing was displayed. Run ./skidbladnir invite again."
  assert_no_secret "$fixture/invite-fail-error"

  chmod 0644 "$fixture/origins.json"
  : >"$SKIDBLADNIR_INVITE_CALLS"
  rm -f -- "$SKIDBLADNIR_INVITE_STARTS"/*
  set +e
  (skidbladnir_invite "$fixture/origins.json" "$fixture/invite-local") >/dev/null 2>"$fixture/mode-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'insecure origins manifest unexpectedly succeeded'
  [[ ! -s "$SKIDBLADNIR_INVITE_CALLS" ]] || fail 'insecure manifest reached a host boundary'
  assert_contains "$fixture/mode-error" 'fleet origins manifest must be a strict, user-owned mode-0600 file'

  # shellcheck source=lib/skidbladnir-operator.sh
  source "$repo_dir/lib/skidbladnir-operator.sh"
  skidbladnir_operator_doctor() { return 1; }
  : >"$SKIDBLADNIR_INVITE_CALLS"
  set +e
  skidbladnir_operator_invite "$fixture/origins.json" "$fixture/invite-local" \
    >"$fixture/invite-preflight-output" 2>"$fixture/invite-preflight-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'fleet invite ignored a failed doctor preflight'
  [[ ! -s "$SKIDBLADNIR_INVITE_CALLS" ]] || fail 'failed doctor preflight reached pairing or QR boundary'
  pass
}

test_operator_doctor_and_service_boundary() {
  # shellcheck source=lib/skidbladnir-operator.sh
  source "$repo_dir/lib/skidbladnir-operator.sh"
  export SKIDBLADNIR_OPERATOR_CALLS="$fixture/operator-calls"

  record_operator_call() {
    local line="$1" field
    shift
    for field in "$@"; do printf -v line '%s %q' "$line" "$field"; done
    printf '%s\n' "$line" >>"$SKIDBLADNIR_OPERATOR_CALLS"
  }
  ssh() {
    local remote_script=""
    if [[ "${*: -4}" == 'bash -o pipefail -s' ]]; then remote_script="$(cat)"; fi
    record_operator_call ssh "$@" "$remote_script"
    case "$remote_script" in
    *'skidbladnir_sha256 "$skidbladnir_release_pin_file"'*)
      case " $* ${SKIDBLADNIR_TEST_REMOTE_PIN_MISMATCH:-} " in
      *' dev-server '*' DevServer '*) printf '%064d\n' 0 ;;
      *' nnandal@arch '*' Arch '*) printf '%064d\n' 0 ;;
      *) skidbladnir_sha256 "$skidbladnir_release_pin_file" ;;
      esac
      return
      ;;
    esac
    case " $* " in
    *' dev-server '*) [[ "${SKIDBLADNIR_FAIL_DEVBOX:-0}" == 0 ]] ;;
    esac
  }
  launchctl() {
    record_operator_call launchctl "$@"
  }
  id() {
    [[ "${1:-}" == -u && $# -eq 1 ]] || return 64
    printf '501\n'
  }
  skidbladnir_operator_doctor_local() {
    printf 'PASS  skidbladnir.local           fixture healthy\n'
  }
  skidbladnir_reconciled_lifetime_digest_local() {
    printf '%064d\n' 1
  }

  uname() { printf 'Linux\n'; }
  set +e
  (skidbladnir_operator_require_macbook) >/dev/null 2>"$fixture/operator-platform-error"
  local status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'MacBook operator accepted Linux'
  assert_contains "$fixture/operator-platform-error" './skidbladnir is the MacBook-only fixed-fleet operator'
  unset -f uname

  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_doctor >"$fixture/operator-doctor-output"
  assert_eq 4 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'fleet doctor pin and remote call count'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 dev-server'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_doctor devbox'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 nnandal@arch'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_doctor arch'
  assert_contains "$fixture/operator-doctor-output" 'Fleet gateway doctor: pass.'

  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  export SKIDBLADNIR_TEST_REMOTE_PIN_MISMATCH=DevServer
  set +e
  skidbladnir_operator_doctor >"$fixture/operator-pin-fail-output" 2>"$fixture/operator-pin-fail-error"
  status=$?
  set -e
  unset SKIDBLADNIR_TEST_REMOTE_PIN_MISMATCH
  [[ "$status" -ne 0 ]] || fail 'fleet doctor accepted a mixed release pin'
  ! grep -F 'dev-server' "$SKIDBLADNIR_OPERATOR_CALLS" | grep -Fq 'skidbladnir_doctor devbox' ||
    fail 'mixed DevServer pin reached its doctor boundary'
  assert_contains "$fixture/operator-pin-fail-error" 'DevServer release pin differs from the MacBook source pin'

  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  export SKIDBLADNIR_FAIL_DEVBOX=1
  set +e
  skidbladnir_operator_doctor >"$fixture/operator-doctor-fail-output" 2>"$fixture/operator-doctor-fail-error"
  status=$?
  set -e
  unset SKIDBLADNIR_FAIL_DEVBOX
  [[ "$status" -ne 0 ]] || fail 'partial fleet doctor unexpectedly succeeded'
  assert_eq 4 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'fleet doctor checks every host after failure'
  assert_contains "$fixture/operator-doctor-fail-error" 'Fleet gateway doctor: fail (1 host).'

  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_service outage Local >"$fixture/operator-service-output"
  skidbladnir_operator_service recover Local >>"$fixture/operator-service-output"
  skidbladnir_operator_service outage DevServer >>"$fixture/operator-service-output"
  skidbladnir_operator_service recover Arch >>"$fixture/operator-service-output"
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'launchctl bootout gui/501/dev.niels.skidbladnir'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'launchctl bootstrap gui/501 /Users/nnandal/Library/LaunchAgents/dev.niels.skidbladnir.plist'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 dev-server systemctl\ --user\ stop\ skidbladnir.service'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 nnandal@arch systemctl\ --user\ start\ skidbladnir.service'
  assert_contains "$fixture/operator-service-output" 'Gateway outage active on Local. tmux and Tailscale Serve were not touched.'
  assert_contains "$fixture/operator-service-output" 'Gateway recovered on Arch. tmux and Tailscale Serve were not touched.'
  ! grep -Eq 'tmux|tailscale' "$SKIDBLADNIR_OPERATOR_CALLS" || fail 'bounded service command touched tmux or Tailscale'

  ssh() {
    local remote_script=""
    if [[ "${*: -4}" == 'bash -o pipefail -s' ]]; then remote_script="$(cat)"; fi
    record_operator_call ssh "$@" "$remote_script"
    case "$remote_script" in
    *'skidbladnir_sha256 "$skidbladnir_release_pin_file"'*)
      skidbladnir_sha256 "$skidbladnir_release_pin_file"
      return
      ;;
    esac
    case " $* " in
    *' dev-server '*) printf '%064d\n' 2 ;;
    *' nnandal@arch '*)
      [[ "${SKIDBLADNIR_FAIL_ARCH_DIGEST:-0}" == 0 ]] || return 9
      printf '%064d\n' 3
      ;;
    *) return 64 ;;
    esac
  }
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  assert_eq "$(printf '%064d' 1)" "$(skidbladnir_operator_reconciled_lifetime_call Local)" 'local reconciled lifetime digest call'
  assert_eq "$(printf '%064d' 2)" "$(skidbladnir_operator_reconciled_lifetime_call DevServer)" 'Devbox reconciled lifetime digest call'
  assert_eq "$(printf '%064d' 3)" "$(skidbladnir_operator_reconciled_lifetime_call Arch)" 'Arch reconciled lifetime digest call'
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_reconciled_lifetime_digests >"$fixture/operator-lifetime-output"
  assert_eq "$(printf 'Local %064d\nDevServer %064d\nArch %064d' 1 2 3)" \
    "$(cat "$fixture/operator-lifetime-output")" 'strict fleet lifetime digest output'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_reconciled_lifetime_digest_local'

  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  export SKIDBLADNIR_FAIL_ARCH_DIGEST=1
  set +e
  skidbladnir_operator_reconciled_lifetime_digests >"$fixture/operator-lifetime-fail-output" \
    2>"$fixture/operator-lifetime-fail-error"
  status=$?
  set -e
  unset SKIDBLADNIR_FAIL_ARCH_DIGEST
  [[ "$status" -ne 0 ]] || fail 'partial lifetime digest unexpectedly succeeded'
  [[ ! -s "$fixture/operator-lifetime-fail-output" ]] || fail 'partial lifetime digest wrote stdout'
  assert_contains "$fixture/operator-lifetime-fail-error" "Couldn't reconcile and read the whole fleet lifetime. Nothing was displayed. Run ./skidbladnir doctor."
  pass
}

test_operator_bash_transport() {
  # shellcheck source=lib/skidbladnir-operator.sh
  source "$repo_dir/lib/skidbladnir-operator.sh"
  local script=$'set -euo pipefail\nprintf "transport ok\\n"'
  ssh() {
    printf '%s\n' "$*" >"$fixture/operator-transport-arguments"
    cat >"$fixture/operator-transport-input"
  }

  skidbladnir_operator_ssh_bash dev-server "$script"
  assert_eq \
    '-T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 dev-server bash -o pipefail -s' \
    "$(cat "$fixture/operator-transport-arguments")" 'remote Bash transport arguments'
  assert_eq "$script" "$(cat "$fixture/operator-transport-input")" 'remote Bash transport stdin'
  pass
}

test_host_acceptance_gate_contract() {
  export SKIDBLADNIR_ACCEPTANCE_CALLS="$fixture/acceptance-calls"
  export SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE=host-acceptance-v1
  : >"$SKIDBLADNIR_ACCEPTANCE_CALLS"
  skidbladnir_credentials_digest_local() { printf '%064d\n' 4; }
  skidbladnir_reconciled_lifetime_digest_local() { printf '%064d\n' 5; }
  skidbladnir_converge() { printf 'converge %s\n' "$1" >>"$SKIDBLADNIR_ACCEPTANCE_CALLS"; }
  skidbladnir_acceptance_service_intent() { printf 'intent %s\n' "$1" >>"$SKIDBLADNIR_ACCEPTANCE_CALLS"; }
  doctor_reset() {
    doctor_failures=0
    doctor_warnings=0
    printf 'doctor-reset\n' >>"$SKIDBLADNIR_ACCEPTANCE_CALLS"
  }
  skidbladnir_doctor() {
    printf 'doctor %s\n' "$1" >>"$SKIDBLADNIR_ACCEPTANCE_CALLS"
    if [[ "${SKIDBLADNIR_ACCEPTANCE_DOCTOR_FAIL:-0}" == 1 ]]; then
      doctor_failures=1
      printf 'FAIL  skidbladnir.fixture          fixture failure\n'
    elif [[ "${SKIDBLADNIR_ACCEPTANCE_DOCTOR_WARN:-0}" == 1 ]]; then
      doctor_warnings=1
      printf 'WARN  skidbladnir.fixture          fixture warning\n'
    else
      printf 'PASS  skidbladnir.fixture          fixture healthy\n'
    fi
  }
  doctor_summary() {
    printf 'summary %s\n' "$1" >>"$SKIDBLADNIR_ACCEPTANCE_CALLS"
    ((doctor_failures == 0))
  }

  skidbladnir_accept_host_local arch Arch >"$fixture/acceptance-output"
  assert_eq 2 "$(grep -Fc 'converge arch' "$SKIDBLADNIR_ACCEPTANCE_CALLS")" 'host acceptance converge count'
  assert_contains "$SKIDBLADNIR_ACCEPTANCE_CALLS" 'intent arch'
  assert_contains "$SKIDBLADNIR_ACCEPTANCE_CALLS" 'doctor arch'
  assert_contains "$SKIDBLADNIR_ACCEPTANCE_CALLS" 'summary Arch Skidbladnir acceptance'
  assert_contains "$fixture/acceptance-output" 'PASS  skidbladnir.accept-host'
  assert_contains "$fixture/acceptance-output" 'NOT_RUN  skidbladnir.accept-host.reboot'

  export SKIDBLADNIR_ACCEPTANCE_DOCTOR_WARN=1
  set +e
  skidbladnir_accept_host_local arch Arch >"$fixture/acceptance-doctor-warn-output" \
    2>"$fixture/acceptance-doctor-warn-error"
  local status=$?
  set -e
  [[ "$status" -eq 0 ]] || fail 'advisory doctor warning blocked host acceptance'
  assert_contains "$fixture/acceptance-doctor-warn-output" 'WARN  skidbladnir.fixture'
  assert_contains "$fixture/acceptance-doctor-warn-output" 'PASS  skidbladnir.accept-host'

  set +e
  skidbladnir_reboot_acceptance_require_health arch Arch \
    >"$fixture/reboot-acceptance-doctor-warn-output" \
    2>"$fixture/reboot-acceptance-doctor-warn-error"
  status=$?
  set -e
  unset SKIDBLADNIR_ACCEPTANCE_DOCTOR_WARN
  [[ "$status" -eq 0 ]] || fail 'advisory doctor warning blocked reboot acceptance'
  assert_contains "$fixture/reboot-acceptance-doctor-warn-output" 'WARN  skidbladnir.fixture'

  export SKIDBLADNIR_ACCEPTANCE_DOCTOR_FAIL=1
  set +e
  skidbladnir_accept_host_local arch Arch >"$fixture/acceptance-doctor-fail-output" \
    2>"$fixture/acceptance-doctor-fail-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'doctor failure did not block host acceptance'
  ! grep -Fq 'PASS  skidbladnir.accept-host' "$fixture/acceptance-doctor-fail-output" ||
    fail 'host acceptance emitted PASS after a doctor failure'
  assert_contains "$fixture/acceptance-doctor-fail-error" \
    'Skidbladnir doctor has failures after convergence on Arch'

  set +e
  (skidbladnir_reboot_acceptance_require_health arch Arch) \
    >"$fixture/reboot-acceptance-doctor-fail-output" \
    2>"$fixture/reboot-acceptance-doctor-fail-error"
  status=$?
  set -e
  unset SKIDBLADNIR_ACCEPTANCE_DOCTOR_FAIL
  [[ "$status" -ne 0 ]] || fail 'doctor failure did not block reboot acceptance'
  assert_contains "$fixture/reboot-acceptance-doctor-fail-error" \
    'Skidbladnir doctor has failures for reboot acceptance on Arch'

  local lifetime_marker="$fixture/acceptance-lifetime-marker"
  skidbladnir_reconciled_lifetime_digest_local() {
    if [[ -e "$lifetime_marker" ]]; then
      printf '%064d\n' 6
    else
      : >"$lifetime_marker"
      printf '%064d\n' 5
    fi
  }
  set +e
  skidbladnir_accept_host_local arch Arch >"$fixture/acceptance-lifetime-fail-output" \
    2>"$fixture/acceptance-lifetime-fail-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'host acceptance passed changed tmux lifetime'
  [[ ! -s "$fixture/acceptance-lifetime-fail-output" ]] ||
    ! grep -Fq 'PASS  skidbladnir.accept-host' "$fixture/acceptance-lifetime-fail-output" ||
    fail 'host acceptance emitted PASS after changed tmux lifetime'
  assert_contains "$fixture/acceptance-lifetime-fail-error" 'Skidbladnir reconciled tmux lifetime changed during acceptance on Arch'

  skidbladnir_accept_host_local() { record_operator_call accept-local "$@"; }
  ssh() {
    local remote_script=""
    if [[ "${*: -4}" == 'bash -o pipefail -s' ]]; then remote_script="$(cat)"; fi
    record_operator_call ssh "$@" "$remote_script"
    case "$remote_script" in
    *'skidbladnir_sha256 "$skidbladnir_release_pin_file"'*)
      skidbladnir_sha256 "$skidbladnir_release_pin_file"
      ;;
    esac
  }
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  unset SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE
  set +e
  skidbladnir_operator_accept_host DevServer --allow-host-convergence \
    --allow-inventory-reconciliation >/dev/null 2>"$fixture/acceptance-gate-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'host acceptance ran without its environment capability'
  [[ ! -s "$SKIDBLADNIR_OPERATOR_CALLS" ]] || fail 'missing acceptance environment capability reached a host boundary'
  assert_contains "$fixture/acceptance-gate-error" 'NOT_RUN  skidbladnir.accept-host'
  assert_contains "$fixture/acceptance-gate-error" 'Usage: ./skidbladnir accept-host <Local|DevServer|Arch> --allow-host-convergence --allow-inventory-reconciliation'

  export SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE=host-acceptance-v1
  set +e
  skidbladnir_operator_accept_host DevServer --allow-host-convergence \
    --wrong-reconciliation-gate >/dev/null 2>"$fixture/acceptance-flag-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'host acceptance accepted the wrong reconciliation flag'
  [[ ! -s "$SKIDBLADNIR_OPERATOR_CALLS" ]] || fail 'wrong acceptance flag reached a host boundary'
  assert_contains "$fixture/acceptance-flag-error" 'NOT_RUN  skidbladnir.accept-host'

  skidbladnir_operator_accept_host Local --allow-host-convergence --allow-inventory-reconciliation
  assert_eq 1 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'Local acceptance boundary count'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'accept-local macos Local'
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_accept_host DevServer --allow-host-convergence --allow-inventory-reconciliation
  assert_eq 2 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'DevServer pin and acceptance boundary count'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 dev-server'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_accept_host_local devbox DevServer'
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_accept_host Arch --allow-host-convergence --allow-inventory-reconciliation
  assert_eq 2 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'Arch pin and acceptance boundary count'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 nnandal@arch'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_accept_host_local arch Arch'
  unset SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE
  pass
}

test_reboot_acceptance_gate_contract() {
  local evidence="$test_home/.local/state/skidbladnir/reboot-acceptance.json"
  local status
  export SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1
  SKIDBLADNIR_TEST_BOOT_DIGEST="$(printf '%064d' 6)"
  SKIDBLADNIR_TEST_CREDENTIALS_DIGEST="$(printf '%064d' 7)"
  SKIDBLADNIR_TEST_LIFETIME_DIGEST="$(printf '%064d' 8)"
  export SKIDBLADNIR_TEST_BOOT_DIGEST SKIDBLADNIR_TEST_CREDENTIALS_DIGEST SKIDBLADNIR_TEST_LIFETIME_DIGEST
  skidbladnir_boot_identity_digest_local() { printf '%s\n' "$SKIDBLADNIR_TEST_BOOT_DIGEST"; }
  skidbladnir_credentials_digest_local() { printf '%s\n' "$SKIDBLADNIR_TEST_CREDENTIALS_DIGEST"; }
  skidbladnir_reconciled_lifetime_digest_local() { printf '%s\n' "$SKIDBLADNIR_TEST_LIFETIME_DIGEST"; }
  skidbladnir_acceptance_service_intent() { :; }
  doctor_reset() {
    doctor_failures=0
    doctor_warnings=0
  }
  skidbladnir_doctor() { :; }
  doctor_summary() { ((doctor_failures == 0 && doctor_warnings == 0)); }

  rm -f -- "$evidence"
  skidbladnir_prepare_reboot_local arch Arch >"$fixture/reboot-prepare-output"
  assert_contains "$fixture/reboot-prepare-output" 'PASS  skidbladnir.accept-host.reboot.prepare Arch reboot checkpoint is ready'
  [[ -f "$evidence" && ! -L "$evidence" ]] || fail 'reboot checkpoint is not a regular file'
  assert_eq 600 "$(skidbladnir_file_mode "$evidence")" 'reboot checkpoint mode'
  jq -e --arg boot "$SKIDBLADNIR_TEST_BOOT_DIGEST" \
    --arg credentials "$SKIDBLADNIR_TEST_CREDENTIALS_DIGEST" '
      type == "object" and
      keys == ["bootDigest","credentialsDigest","label","platform","releasePinDigest","schemaVersion"] and
      .schemaVersion == 1 and .platform == "arch" and .label == "Arch" and
      .bootDigest == $boot and .credentialsDigest == $credentials and
      (.releasePinDigest | test("^[0-9a-f]{64}$"))
    ' "$evidence" >/dev/null || fail 'reboot checkpoint schema differs'

  set +e
  skidbladnir_verify_reboot_local arch Arch >"$fixture/reboot-same-boot-output" \
    2>"$fixture/reboot-same-boot-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'reboot verification passed without a reboot'
  [[ -f "$evidence" ]] || fail 'same-boot verification removed the checkpoint'
  assert_contains "$fixture/reboot-same-boot-error" 'NOT_RUN  skidbladnir.accept-host.reboot Arch boot identity has not changed'

  SKIDBLADNIR_TEST_BOOT_DIGEST="$(printf '%064d' 9)"
  SKIDBLADNIR_TEST_LIFETIME_DIGEST="$(printf '%064d' 9)"
  export SKIDBLADNIR_TEST_BOOT_DIGEST SKIDBLADNIR_TEST_LIFETIME_DIGEST
  skidbladnir_verify_reboot_local arch Arch >"$fixture/reboot-verify-output"
  assert_contains "$fixture/reboot-verify-output" 'PASS  skidbladnir.accept-host.reboot Arch reboot/login persistence preserved release and credentials'
  [[ ! -e "$evidence" && ! -L "$evidence" ]] || fail 'successful reboot verification retained the checkpoint'

  SKIDBLADNIR_TEST_BOOT_DIGEST="$(printf '%064d' 1)"
  export SKIDBLADNIR_TEST_BOOT_DIGEST
  skidbladnir_prepare_reboot_local arch Arch >/dev/null
  SKIDBLADNIR_TEST_BOOT_DIGEST="$(printf '%064d' 2)"
  SKIDBLADNIR_TEST_CREDENTIALS_DIGEST="$(printf '%064d' 3)"
  export SKIDBLADNIR_TEST_BOOT_DIGEST SKIDBLADNIR_TEST_CREDENTIALS_DIGEST
  set +e
  skidbladnir_verify_reboot_local arch Arch >"$fixture/reboot-credentials-output" \
    2>"$fixture/reboot-credentials-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'reboot verification passed changed credentials'
  [[ -f "$evidence" ]] || fail 'failed reboot verification removed the checkpoint'
  ! grep -Fq 'PASS  skidbladnir.accept-host.reboot ' "$fixture/reboot-credentials-output" ||
    fail 'failed reboot verification emitted PASS'
  assert_contains "$fixture/reboot-credentials-error" 'Skidbladnir credentials changed across reboot on Arch'
  /bin/unlink "$evidence"

  skidbladnir_prepare_reboot_local() { record_operator_call reboot-local "$@"; }
  skidbladnir_verify_reboot_local() { record_operator_call reboot-local "$@"; }
  ssh() {
    local remote_script=""
    if [[ "${*: -4}" == 'bash -o pipefail -s' ]]; then remote_script="$(cat)"; fi
    record_operator_call ssh "$@" "$remote_script"
    case "$remote_script" in
    *'skidbladnir_sha256 "$skidbladnir_release_pin_file"'*)
      skidbladnir_sha256 "$skidbladnir_release_pin_file"
      ;;
    esac
  }
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  unset SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE
  set +e
  skidbladnir_operator_reboot_acceptance prepare Local --allow-reboot-acceptance \
    >/dev/null 2>"$fixture/reboot-gate-error"
  status=$?
  set -e
  [[ "$status" -ne 0 ]] || fail 'reboot acceptance ran without its environment capability'
  [[ ! -s "$SKIDBLADNIR_OPERATOR_CALLS" ]] || fail 'missing reboot capability reached a host boundary'
  assert_contains "$fixture/reboot-gate-error" 'NOT_RUN  skidbladnir.accept-host.reboot'

  export SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1
  skidbladnir_operator_reboot_acceptance prepare Local --allow-reboot-acceptance
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'reboot-local macos Local'
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_reboot_acceptance verify DevServer --allow-reboot-acceptance
  assert_eq 2 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'DevServer reboot pin and verification boundary count'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 dev-server'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_verify_reboot_local devbox DevServer'
  : >"$SKIDBLADNIR_OPERATOR_CALLS"
  skidbladnir_operator_reboot_acceptance prepare Arch --allow-reboot-acceptance
  assert_eq 2 "$(wc -l <"$SKIDBLADNIR_OPERATOR_CALLS" | tr -d '[:space:]')" 'Arch reboot pin and preparation boundary count'
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'skidbladnir_prepare_reboot_local arch Arch'
  unset SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE
  unset SKIDBLADNIR_TEST_BOOT_DIGEST SKIDBLADNIR_TEST_CREDENTIALS_DIGEST SKIDBLADNIR_TEST_LIFETIME_DIGEST
  pass
}

test_macos_tmux_tracks_homebrew_stable
test_assets_and_operator_copy
test_converge_and_doctor
test_invite_success_and_fail_closed
test_operator_bash_transport
test_operator_doctor_and_service_boundary
test_host_acceptance_gate_contract
test_reboot_acceptance_gate_contract

printf 'PASS: %d Skidbladnir public-fleet test groups\n' "$tests_run"
