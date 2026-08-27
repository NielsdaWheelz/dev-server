#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-skidbladnir-test.XXXXXX")"
test_home="$fixture/home"
test_bin="$fixture/bin"
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

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_exact_line_once() {
  local file="$1"
  local line="$2"
  [[ "$(grep -Fxc -- "$line" "$file" || true)" == 1 ]] ||
    fail "$file must contain exactly once: $line"
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

test_assets_and_operator_copy() {
  local pin="$repo_dir/assets/skidbladnir/release-pin.json"
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

  local row config platform tmux_path tmux_version home
  for row in \
    'devbox Linux /usr/bin/tmux tmux_3.4 /home/niels' \
    'arch Linux /usr/bin/tmux tmux_3.7c /home/niels' \
    'macbook Darwin /opt/homebrew/bin/tmux tmux_3.7b /Users/nnandal'; do
    read -r config platform tmux_path tmux_version home <<<"$row"
    config="$repo_dir/assets/skidbladnir/host-config-$config.json"
    tmux_version="${tmux_version/_/ }"
    jq -e --arg platform "$platform" --arg tmux_path "$tmux_path" \
      --arg tmux_version "$tmux_version" --arg home "$home" '
      type == "object" and keys == ["codexNodeEntrypoint", "platform", "profiles", "tmux"] and
      .platform == $platform and .tmux == {path: $tmux_path, version: $tmux_version} and
      .codexNodeEntrypoint == ($home + "/.local/bin/codex") and
      .profiles == [
        {key:"personal",label:"Codex · Personal",command:($home + "/bin/codex-personal"),environment:[{name:"CODEX_HOME",value:($home + "/.codex-personal")}],foregroundSignatures:[{executableBase:"codex"},{executableBase:"node",argument1:($home + "/.local/bin/codex")}],arguments:["--dangerously-bypass-approvals-and-sandbox"]},
        {key:"work",label:"Codex · Work",command:($home + "/bin/codex-work"),environment:[{name:"CODEX_HOME",value:($home + "/.codex-work")}],foregroundSignatures:[{executableBase:"codex"},{executableBase:"node",argument1:($home + "/.local/bin/codex")}],arguments:["--dangerously-bypass-approvals-and-sandbox"]},
        {key:"work2",label:"Codex · Work 2",command:($home + "/bin/codex-work2"),environment:[{name:"CODEX_HOME",value:($home + "/.codex-work2")}],foregroundSignatures:[{executableBase:"codex"},{executableBase:"node",argument1:($home + "/.local/bin/codex")}],arguments:["--dangerously-bypass-approvals-and-sandbox"]},
        {key:"claude-personal",label:"Claude · Personal",command:($home + "/bin/claude-personal"),environment:[{name:"CLAUDE_CONFIG_DIR",value:($home + "/.claude-personal")}],foregroundSignatures:[{argument0:($home + "/.local/bin/claude")}],arguments:["--permission-mode","auto"]},
        {key:"claude-work",label:"Claude · Work",command:($home + "/bin/claude-work"),environment:[{name:"CLAUDE_CONFIG_DIR",value:($home + "/.claude-work")}],foregroundSignatures:[{argument0:($home + "/.local/bin/claude")}],arguments:["--permission-mode","auto"]}
      ]
    ' "$config" >/dev/null || fail "strict host config differs: $config"
  done

  local unit="$repo_dir/assets/skidbladnir/skidbladnir.service"
  assert_exact_line_once "$unit" 'Type=simple'
  assert_exact_line_once "$unit" 'UnsetEnvironment=TMUX TMUX_PANE TMUX_TMPDIR'
  assert_exact_line_once "$unit" 'ExecStart=%h/.local/bin/skidbladnir-launch gateway --listen=127.0.0.1:7341 --bearer-file=%h/.config/skidbladnir/bearer --catalogue-path=%h/.local/share/skidbladnir/characters.json --machine-handle-file=%h/.config/skidbladnir/machine-handle --host-config=%h/.config/skidbladnir/host-config.json'
  assert_exact_line_once "$unit" 'Restart=on-failure'
  assert_exact_line_once "$unit" 'RestartSec=2s'
  assert_exact_line_once "$unit" 'TimeoutStopSec=10s'
  assert_exact_line_once "$unit" 'KillMode=process'
  assert_exact_line_once "$unit" 'WantedBy=default.target'

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
  ! grep -Fq 'tailscale serve reset' "$repo_dir/lib/skidbladnir.sh" || fail 'convergence resets unrelated Tailscale Serve state'
  assert_contains "$repo_dir/lib/skidbladnir-invite.sh" \
    'Fleet invite ready. It expires in 5 minutes and works once. On the phone, open Skíðblaðnir and tap Connect.'
  assert_contains "$repo_dir/lib/skidbladnir-invite.sh" \
    "Couldn't create the whole fleet invite. Nothing was displayed. Run ./skidbladnir invite again."
  ! grep -Eq -- '--arg[^[:cntrl:]]*(token|result|response|bearer)' "$repo_dir/lib/skidbladnir-invite.sh" ||
    fail 'fleet invitation passes credential material in process arguments'
  assert_contains "$repo_dir/workstation" 'skidbladnir_converge "$(platform_id)"'
  assert_contains "$repo_dir/workstation" 'skidbladnir_preflight_tmux_runtime "$(platform_id)"'
  assert_contains "$repo_dir/workstation" 'skidbladnir_require_tmux_runtime "$(platform_id)"'
  assert_contains "$repo_dir/lib/packages-arch.sh" 'pacman_arguments+=(--ignore tmux)'
  assert_contains "$repo_dir/lib/packages-arch.sh" 'sudo systemctl enable --now sshd.service'
  assert_contains "$repo_dir/lib/packages-arch.sh" 'doctor_pass package.ssh "OpenSSH enabled for fixed tailnet operator access"'
  assert_contains "$repo_dir/lib/packages-macos.sh" 'HOMEBREW_NO_AUTO_UPDATE=1 brew bundle'
  assert_contains "$repo_dir/ansible/roles/base/tasks/main.yml" "failed_when: devbox_tmux_version.stdout != 'tmux 3.4'"
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
  archive_sha="$(shasum -a 256 "$fixture/skidbladnir-linux-amd64.tar.gz" | awk '{print $1}')"
  jq -n --arg digest "$archive_sha" --arg source "$source_sha" \
    '{version:"v1.2.3",sourceSha:$source,androidApkSha256:$digest,androidSigningCertAssetSha256:$digest,linuxAmd64Sha256:$digest,darwinArm64Sha256:$digest,sha256SumsAssetSha256:$digest}' \
    >"$fixture/release-pin.json"

  cat >"$fixture/host-config.json" <<EOF
{
  "platform": "Linux",
  "tmux": {"path": "$test_bin/tmux", "version": "tmux 3.7c"},
  "codexNodeEntrypoint": "$test_home/.local/bin/codex",
  "profiles": [
    {"key":"personal","label":"Codex · Personal","command":"$test_home/bin/codex-personal","environment":[{"name":"CODEX_HOME","value":"$test_home/.codex-personal"}],"foregroundSignatures":[{"executableBase":"codex"}],"arguments":[]}
  ]
}
EOF
}

write_runtime_boundaries() {
  cat >"$test_bin/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' --config - '* ]]; then
  request_config="$(cat)"
  if [[ "${1:-}" != -q || " $* " != *' --noproxy * '* ]]; then
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
  if [[ " $* " != *' --output /dev/null '* && -n "${SKIDBLADNIR_TEST_INVENTORY:-}" ]]; then
    printf '%s\n' "$SKIDBLADNIR_TEST_INVENTORY"
  fi
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
  *' is-active '*) [[ -f "$SKIDBLADNIR_TEST_SERVICE_STATE" ]] ;;
  *' is-enabled '*) [[ -f "$SKIDBLADNIR_TEST_SERVICE_STATE" ]] ;;
  *' enable --now '*) touch "$SKIDBLADNIR_TEST_SERVICE_STATE" ;;
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
  'status --json') printf '{"BackendState":"Running"}\n' ;;
  'serve status')
    if [[ -n "${SKIDBLADNIR_TEST_SERVE_STATUS:-}" ]]; then
      printf '%s\n' "$SKIDBLADNIR_TEST_SERVE_STATUS"
    else
      printf '%s\n' '{"TCP":{"8443":{"HTTPS":true}},"Web":{"host.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}}}'
    fi
    ;;
esac
EOF
  cat >"$test_bin/tmux" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == -V ]]
printf 'tmux 3.7c\n'
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
  : >"$SKIDBLADNIR_TEST_CALLS"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/doctor.sh
  source "$repo_dir/lib/doctor.sh"
  # shellcheck source=lib/skidbladnir.sh
  source "$repo_dir/lib/skidbladnir.sh"
  # dev_server_home reads this shared library seam.
  # shellcheck disable=SC2034
  dev_server_home_dir="$test_home"
  # shellcheck disable=SC2034
  skidbladnir_release_pin_file="$fixture/release-pin.json"
  skidbladnir_host_config_source() { printf '%s\n' "$fixture/host-config.json"; }
  skidbladnir_tailscale_cli() { printf '%s\n' "$test_bin/tailscale"; }

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
  sed 's/"version": "v1.2.3"/"version": "v1.2.3", "version": "v1.2.3"/' \
    "$fixture/release-pin.valid.json" >"$skidbladnir_release_pin_file"
  if skidbladnir_release_values arch >/dev/null 2>&1; then
    fail 'release pin accepted a duplicate version member'
  fi
  mv "$fixture/release-pin.valid.json" "$skidbladnir_release_pin_file"

  local old_path="$PATH"
  PATH="$test_bin:$PATH"
  export PATH
  skidbladnir_converge arch
  local handle_before bearer_before
  handle_before="$(cat "$test_home/.config/skidbladnir/machine-handle")"
  bearer_before="$(cat "$test_home/.config/skidbladnir/bearer")"
  assert_eq mh-11111111111111111111111111111111 "$handle_before" 'created machine handle'
  assert_eq AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA "$bearer_before" 'created bearer'
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
  export SKIDBLADNIR_TEST_SERVE_STATUS='{"TCP":{"8443":{"HTTPS":true}},"Web":{"host.example.ts.net:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:7341"}}}}}'
  skidbladnir_configure_serve "$test_bin/tailscale"
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'tailscale serve --yes --https=8443 --set-path=/ off'
  unset SKIDBLADNIR_TEST_SERVE_STATUS

  local doctor_output="$fixture/doctor-output"
  doctor_reset
  skidbladnir_doctor arch >"$doctor_output"
  assert_eq 9 "$(grep -Ec '^PASS  skidbladnir[.]' "$doctor_output")" 'healthy doctor PASS fact count'
  assert_contains "$doctor_output" 'skidbladnir.artifact.version'
  assert_contains "$doctor_output" 'v1.2.3 at source 1111111111111111111111111111111111111111'
  assert_contains "$doctor_output" 'skidbladnir.artifact.digest'
  assert_contains "$doctor_output" 'pinned archive and all installed release members match'
  assert_contains "$doctor_output" 'skidbladnir.config'
  assert_contains "$doctor_output" 'strict arch host config, hooks, and notifier installed'
  assert_contains "$doctor_output" 'skidbladnir.secrets'
  assert_contains "$doctor_output" 'machine handle and bearer are canonical mode-0600 files'
  assert_contains "$doctor_output" 'skidbladnir.service'
  assert_contains "$doctor_output" 'systemd user definition matches and is enabled and active'
  assert_contains "$doctor_output" 'skidbladnir.loopback'
  assert_contains "$doctor_output" 'authenticated tmux-free loopback pressure endpoint is healthy'
  assert_contains "$doctor_output" 'skidbladnir.serve'
  assert_contains "$doctor_output" 'private HTTPS 8443 exposes only loopback /v1'
  assert_contains "$doctor_output" 'skidbladnir.tmux'
  assert_contains "$doctor_output" 'tmux 3.7c available at the configured path'
  assert_contains "$doctor_output" 'skidbladnir.tailscale'
  assert_contains "$doctor_output" 'Tailscale is signed in'
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'curl-config url\ =\ \"http://127.0.0.1:7341/v1/pressure\"'
  [[ ! -e "$SKIDBLADNIR_TEST_CURL_LEAK" ]] || fail 'credential-bearing curl honored ambient config or proxy state'
  ! grep -Fq '/v1/sessions' "$SKIDBLADNIR_TEST_CALLS" || fail 'doctor reached the normalizing inventory endpoint'
  bearer="$bearer_before"
  arch_token="" devbox_token="" local_token=""
  assert_no_secret "$doctor_output"
  local xtrace_output="$fixture/doctor-xtrace"
  {
    set -x
    doctor_reset
    skidbladnir_doctor arch >/dev/null
    set +x
  } 2>"$xtrace_output"
  assert_no_secret "$xtrace_output"

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
  SKIDBLADNIR_TEST_INVENTORY='{"machine":{"handle":"mh-11111111111111111111111111111111"},"observedAt":"first","sessions":[{"id":"$2","tmuxName":"second","identityToken":"v1-22222222222222222222222222222222.20.30.2","objective":"private two"},{"id":"$1","tmuxName":"first","identityToken":"v1-11111111111111111111111111111111.20.30.1","objective":"private one"}]}'
  local lifetime_before lifetime_after
  lifetime_before="$(skidbladnir_reconciled_lifetime_digest_local)"
  SKIDBLADNIR_TEST_INVENTORY='{"machine":{"handle":"mh-11111111111111111111111111111111"},"observedAt":"later","sessions":[{"id":"$1","tmuxName":"first","identityToken":"v1-11111111111111111111111111111111.20.30.1","objective":"changed"},{"id":"$2","tmuxName":"second","identityToken":"v1-22222222222222222222222222222222.20.30.2","attention":true}]}'
  lifetime_after="$(skidbladnir_reconciled_lifetime_digest_local)"
  assert_eq "$lifetime_before" "$lifetime_after" 'lifetime digest ignores inventory order and mutable card facts'
  [[ "$lifetime_before" =~ ^[0-9a-f]{64}$ ]] || fail 'lifetime digest is not one lowercase SHA-256'
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
  assert_contains "$fixture/drift-output" 'owned host config, hooks, or notifier differs; run the platform converge command'
  cp "$fixture/host-config.json" "$test_home/.config/skidbladnir/host-config.json"
  chmod 0600 "$test_home/.config/skidbladnir/host-config.json"

  printf '\n' >>"$test_home/.codex-work/hooks.json"
  doctor_reset
  skidbladnir_doctor arch >"$fixture/hooks-drift-output" || true
  assert_contains "$fixture/hooks-drift-output" 'FAIL  skidbladnir.config'
  cp "$repo_dir/assets/skidbladnir/status-hooks-linux.json" "$test_home/.codex-work/hooks.json"
  chmod 0600 "$test_home/.codex-work/hooks.json"

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
  skidbladnir_install_macos_service "$test_home"
  assert_contains "$SKIDBLADNIR_TEST_CALLS" 'launchctl kickstart gui/501/dev.niels.skidbladnir'
  ! grep -Fq 'launchctl bootout' "$SKIDBLADNIR_TEST_CALLS" || fail 'unchanged loaded LaunchAgent was restarted'

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
  export SKIDBLADNIR_TEST_FAIL_INSTALL_TARGET='.characters.json.skidbladnir.'
  export SKIDBLADNIR_TEST_FAIL_INSTALL_ONCE="$fixture/install-failed-once"
  set +e
  skidbladnir_converge arch >/dev/null 2>"$fixture/release-transaction-error"
  local transaction_status=$?
  set -e
  unset SKIDBLADNIR_TEST_FAIL_INSTALL_TARGET SKIDBLADNIR_TEST_FAIL_INSTALL_ONCE
  [[ "$transaction_status" -ne 0 ]] || fail 'injected release promotion failure unexpectedly succeeded'
  assert_eq "$old_binary_sha" "$(skidbladnir_sha256 "$test_home/.local/bin/skidbladnir")" \
    'failed release transaction preserved binary'
  assert_eq "$old_catalogue_sha" "$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/characters.json")" \
    'failed release transaction preserved catalogue'
  assert_eq "$old_manifest_sha" "$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/release.json")" \
    'failed release transaction preserved manifest'
  assert_eq "$old_bundle_sha" "$(skidbladnir_sha256 "$test_home/.local/share/skidbladnir/release-bundle.tar.gz")" \
    'failed release transaction preserved retained bundle'

  skidbladnir_begin_release_transaction "$test_home" "$test_home/.local/share/skidbladnir"
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
  skidbladnir_recover_release_transaction "$test_home" "$test_home/.local/share/skidbladnir"
  assert_eq "$old_binary_sha" "$(skidbladnir_sha256 "$test_home/.local/bin/skidbladnir")" \
    'crash recovery restored binary'
  [[ ! -e "$test_home/.local/share/skidbladnir/.release-transaction" ]] ||
    fail 'crash recovery left its release transaction journal'
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
    *' arch '*) target=Arch ;;
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
    *' arch '*)
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
  assert_contains "$SKIDBLADNIR_INVITE_CALLS" 'ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 arch'
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
      *' arch '*' Arch '*) printf '%064d\n' 0 ;;
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
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 arch'
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
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 arch systemctl\ --user\ start\ skidbladnir.service'
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
    *' arch '*)
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
    if [[ "${SKIDBLADNIR_ACCEPTANCE_DOCTOR_WARN:-0}" == 1 ]]; then
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
  skidbladnir_accept_host_local arch Arch >"$fixture/acceptance-doctor-fail-output" \
    2>"$fixture/acceptance-doctor-fail-error"
  local status=$?
  set -e
  unset SKIDBLADNIR_ACCEPTANCE_DOCTOR_WARN
  [[ "$status" -ne 0 ]] || fail 'host acceptance passed an incomplete doctor'
  [[ ! -s "$fixture/acceptance-doctor-fail-output" ]] ||
    ! grep -Fq 'PASS  skidbladnir.accept-host' "$fixture/acceptance-doctor-fail-output" ||
    fail 'host acceptance emitted PASS after an incomplete doctor'
  assert_contains "$fixture/acceptance-doctor-fail-error" 'Skidbladnir doctor is not completely healthy after convergence on Arch'

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
  assert_contains "$SKIDBLADNIR_OPERATOR_CALLS" 'ConnectionAttempts=1 arch'
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

test_assets_and_operator_copy
test_converge_and_doctor
test_invite_success_and_fail_closed
test_operator_bash_transport
test_operator_doctor_and_service_boundary
test_host_acceptance_gate_contract
test_reboot_acceptance_gate_contract

printf 'PASS: %d Skidbladnir public-fleet test groups\n' "$tests_run"
