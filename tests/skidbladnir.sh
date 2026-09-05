#!/usr/bin/env bash
# shellcheck disable=SC2034 # Shared-library seams are consumed after sourcing.
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-skidbladnir.XXXXXX")"
trap 'rm -rf -- "$fixture"' EXIT

# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=lib/skidbladnir.sh
source "$repo_dir/lib/skidbladnir.sh"

tests_run=0
case_dir=''
test_home=''
test_calls=''
test_service_active=''
test_service_enabled=''
test_service_version=''
test_fail_marker=''
test_fail_action=''
test_reject_version=''

fail() {
  printf 'FAIL  skidbladnir: %s\n' "$*" >&2
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
  local text="$2"
  local label="$3"
  grep -Fq -- "$text" "$path" || fail "$label: <$text> not found in $path"
}

assert_mode() {
  assert_eq "${1#0}" "$(file_mode "$2")" "$3"
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
  skidbladnir_unit_changed=0
  skidbladnir_activation_status=''
  skidbladnir_directory_changed=0
  skidbladnir_integration_changed=0
  skidbladnir_enablement_changed=0
  skidbladnir_command_installed=0
}

write_fake_tailscale() {
  local target="$1"
  cat >"$target" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'tailscale' >>"$SKID_TEST_CALLS"
printf ' %q' "$@" >>"$SKID_TEST_CALLS"
printf '\n' >>"$SKID_TEST_CALLS"
case "${1:-} ${2:-}" in
'status --json')
  cat "$SKID_TEST_TAILSCALE_STATUS"
  ;;
'serve status')
  cat "$SKID_TEST_SERVE_STATUS"
  ;;
'serve --bg')
  hostname="$(jq -r '.Self.DNSName[:-1]' "$SKID_TEST_TAILSCALE_STATUS")"
  jq -cn --arg key "$hostname:8443" \
    '{TCP:{"8443":{HTTPS:true}},Web:{($key):{Handlers:{"/v1":{Proxy:"http://127.0.0.1:7341/v1"}}}}}' \
    >"$SKID_TEST_SERVE_STATUS.next"
  mv "$SKID_TEST_SERVE_STATUS.next" "$SKID_TEST_SERVE_STATUS"
  ;;
*) exit 64 ;;
esac
SH
  chmod 0755 "$target"
}

setup_case() {
  local name="$1"
  case_dir="$fixture/$name"
  test_home="$case_dir/home"
  test_calls="$case_dir/calls"
  test_service_active="$case_dir/service-active"
  test_service_enabled="$case_dir/service-enabled"
  test_service_version="$case_dir/service-version"
  test_fail_marker="$case_dir/fail-once"
  test_fail_action=''
  test_reject_version=''
  mkdir -p "$test_home" "$case_dir/assets" "$case_dir/bin"
  mkdir -p "$test_home/.local/bin"
  cat >"$test_home/.local/bin/codex" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "$*" == 'features list' ]]
SH
  chmod 0755 "$test_home/.local/bin/codex"
  cp -R "$repo_dir/assets/skidbladnir" "$case_dir/assets/skidbladnir"
  : >"$test_calls"
  printf '%s\n' '{"BackendState":"Running","Self":{"DNSName":"test.example.ts.net."}}' \
    >"$case_dir/tailscale-status.json"
  printf '%s\n' '{}' >"$case_dir/serve-status.json"
  write_fake_tailscale "$case_dir/bin/tailscale"

  dev_server_home_dir="$test_home"
  dev_server_assets_root="$case_dir/assets"
  skidbladnir_release_pin_file="$case_dir/release-pin.json"
  export SKID_TEST_CALLS="$test_calls"
  export SKID_TEST_TAILSCALE_STATUS="$case_dir/tailscale-status.json"
  export SKID_TEST_SERVE_STATUS="$case_dir/serve-status.json"
  reset_results
}

write_release() {
  local version="$1"
  local source_sha="$2"
  local mode="${3:-normal}"
  local release="$case_dir/release"
  local binary_version="$version"
  local binary_source="$source_sha"
  local manifest_source="$source_sha"
  local archive_sha

  rm -rf -- "$release"
  mkdir "$release"
  [[ "$mode" != bad_binary ]] || binary_version=v9.9.9
  [[ "$mode" != bad_manifest ]] || manifest_source=0000000000000000000000000000000000000000
  {
    printf '%s\n' '#!/usr/bin/env bash' 'set -euo pipefail'
    printf 'version=%q\nsource=%q\n' "$binary_version" "$binary_source"
    printf '%s\n' \
      'case "${1:-}" in' \
      'version) printf "%s %s\n" "$version" "$source" ;;' \
      'machine) target="${3#--file=}"; [[ ! -e "$target" && ! -L "$target" ]] || exit 73; printf "mh-0123456789abcdef0123456789abcdef\n" >"$target" ;;' \
      'bearer) target="${3#--file=}"; [[ ! -e "$target" && ! -L "$target" ]] || exit 73; printf "000000000000000000000000000000000000000000E\n" >"$target" ;;' \
      '*) exit 64 ;;' \
      'esac'
  } >"$release/skidbladnir"
  chmod 0755 "$release/skidbladnir"
  printf '%s\n' '{"characters":[]}' >"$release/characters.json"
  jq -n --arg platform linux-amd64 --arg source "$manifest_source" --arg version "$version" \
    '{platform:$platform,sourceSha:$source,version:$version}' >"$release/release.json"
  if [[ "$mode" == extra_member ]]; then
    printf 'unexpected\n' >"$release/extra"
    tar -czf "$case_dir/release.tar.gz" -C "$release" \
      skidbladnir characters.json release.json extra
  else
    tar -czf "$case_dir/release.tar.gz" -C "$release" \
      skidbladnir characters.json release.json
  fi
  archive_sha="$(dev_server_sha256 "$case_dir/release.tar.gz")"
  jq -n --arg version "$version" --arg source "$source_sha" --arg digest "$archive_sha" '
    {
      schemaVersion:1,
      version:$version,
      sourceSha:$source,
      artifacts:{
        "darwin-arm64":{
          url:("https://github.com/NielsdaWheelz/skidbladnir/releases/download/" + $version + "/skidbladnir-darwin-arm64.tar.gz"),
          sha256:$digest
        },
        "linux-amd64":{
          url:("https://github.com/NielsdaWheelz/skidbladnir/releases/download/" + $version + "/skidbladnir-linux-amd64.tar.gz"),
          sha256:$digest
        }
      }
    }
  ' >"$skidbladnir_release_pin_file"
  export SKID_TEST_ARCHIVE="$case_dir/release.tar.gz"
}

skidbladnir_download() {
  printf 'download %s\n' "$1" >>"$test_calls"
  cp "$SKID_TEST_ARCHIVE" "$2"
}

skidbladnir_tailscale_cli() {
  printf '%s\n' "$case_dir/bin/tailscale"
}

systemctl() {
  printf 'systemctl' >>"$test_calls"
  printf ' %q' "$@" >>"$test_calls"
  printf '\n' >>"$test_calls"
  case " $* " in
  *' is-active '*)
    [[ -f "$test_service_active" ]] && return 0
    return 3
    ;;
  *' is-enabled '*) [[ -f "$test_service_enabled" ]] ;;
  *' enable '*) : >"$test_service_enabled" ;;
  *' disable '*) rm -f -- "$test_service_enabled" ;;
  *' start '* | *' restart '*)
    local action candidate_version
    if [[ " $* " == *' restart '* ]]; then action=restart; else action=start; fi
    if [[ "$test_fail_action" == "$action" && ! -e "$test_fail_marker" ]]; then
      : >"$test_fail_marker"
      return 73
    fi
    candidate_version="$(jq -r '.version' "$test_home/.local/share/skidbladnir/current/release.json")"
    [[ "$candidate_version" != "$test_reject_version" ]] || return 74
    : >"$test_service_active"
    printf '%s\n' "$candidate_version" >"$test_service_version"
    ;;
  *' stop '*) rm -f -- "$test_service_active" ;;
  *' show '*) printf '%s\n' "$$" ;;
  *' daemon-reload '*) : ;;
  *) return 64 ;;
  esac
}

curl() {
  local curl_config
  [[ -f "$test_service_active" ]] || return 7
  curl_config="$(cat)"
  grep -Fq "header = \"Authorization: Bearer $(cat "$test_home/.config/skidbladnir/bearer")\"" \
    <<<"$curl_config" || return 22
  grep -Fq "header = \"Skidbladnir-Machine: $(cat "$test_home/.config/skidbladnir/machine-handle")\"" \
    <<<"$curl_config" || return 22
  printf '%s\n' '{"current":{},"history":[],"unsupported":[]}'
}

skidbladnir_running_binary_matches() {
  local runtime_ref="${3:-current}"
  local expected
  [[ -f "$test_service_active" && -f "$test_service_version" ]] || return 1
  expected="$(jq -r '.version' "$test_home/.local/share/skidbladnir/$runtime_ref/release.json")"
  [[ "$(cat "$test_service_version")" == "$expected" ]]
}

count_calls() {
  local pattern="$1"
  grep -Ec "$pattern" "$test_calls" 2>/dev/null || true
}

test_pin_and_config_contract() (
  local pin="$repo_dir/assets/skidbladnir/release-pin.json"
  local valid="$fixture/pin-valid.json"
  local duplicate="$fixture/pin-duplicate.json"
  local oversized="$fixture/pin-oversized.json"
  local line

  skidbladnir_release_pin_file="$pin"
  line="$(skidbladnir_release_values arch)" || fail 'current release pin was rejected'
  assert_eq v0.2.27 "${line%%$'\t'*}" 'current release version'
  [[ "$line" == *$'\thttps://github.com/NielsdaWheelz/skidbladnir/releases/download/v0.2.27/skidbladnir-linux-amd64.tar.gz\tf28d1695f5848fde126d4e5198ddb03fa389710f38c491cc6dd4416a2da73f66\tlinux-amd64' ]] ||
    fail 'current Linux URL or digest differs'
  cp "$pin" "$valid"
  sed 's/"version": "v0.2.27"/"version": "v0.2.27", "version": "v0.2.27"/' \
    "$valid" >"$duplicate"
  skidbladnir_release_pin_file="$duplicate"
  if skidbladnir_release_values arch >/dev/null 2>&1; then
    fail 'duplicate release-pin key was accepted'
  fi
  cp "$valid" "$oversized"
  printf '%04100d' 0 >>"$oversized"
  skidbladnir_release_pin_file="$oversized"
  if skidbladnir_release_values arch >/dev/null 2>&1; then
    fail 'oversized release pin was accepted'
  fi

  dev_server_assets_root="$repo_dir/assets"
  for line in macos arch devbox; do
    skidbladnir_host_config_valid "$(skidbladnir_host_config_source "$line")" "$line" ||
      fail "$line host config was rejected"
  done
  jq -e '
    all(.profiles[] | select(.provider == "Codex"); .arguments == []) and
    all(.profiles[] | select(.provider == "Claude");
      .command as $command |
      ($command |
        if endswith("/.local/bin/claude")
        then sub("/\\.local/bin/claude$"; "")
        else sub("/bin/claude-work$"; "") end) as $home |
      .arguments == ["--plugin-dir", ($home + "/.local/share/skidbladnir/claude-agent-identity")])
  ' \
    "$repo_dir"/assets/skidbladnir/host-config-*.json >/dev/null ||
    fail 'safe host configs do not activate only the fixed Claude plugin'
  if grep -En 'dangerously-bypass-approvals-and-sandbox|permission-mode|skip-permissions' \
    "$repo_dir"/assets/skidbladnir/host-config-*.json >"$fixture/unsafe-host-config"; then
    fail 'host configs contain an approval or permission bypass'
  fi
)

test_platform_scoped_declared_inputs() (
  local platform_root="$fixture/platform-assets"

  mkdir -p "$platform_root/linux" "$platform_root/macos"
  cp -R "$repo_dir/assets/skidbladnir" "$platform_root/linux/skidbladnir"
  cp -R "$repo_dir/assets/skidbladnir" "$platform_root/macos/skidbladnir"

  rm "$platform_root/linux/skidbladnir/skid-notify-macbook" \
    "$platform_root/linux/skidbladnir/dev.niels.skidbladnir.plist"
  dev_server_assets_root="$platform_root/linux"
  skidbladnir_release_pin_file="$platform_root/linux/skidbladnir/release-pin.json"
  skidbladnir_validate_declared_inputs devbox

  rm "$platform_root/macos/skidbladnir/skid-notify-linux" \
    "$platform_root/macos/skidbladnir/skidbladnir.service"
  dev_server_assets_root="$platform_root/macos"
  skidbladnir_release_pin_file="$platform_root/macos/skidbladnir/release-pin.json"
  skidbladnir_validate_declared_inputs macos
)

test_fresh_noop_and_exact_activation() (
  local source_sha=1111111111111111111111111111111111111111
  local current inode_before output="$fixture/happy-output" signing_sha stale_stage
  setup_case happy
  write_release v1.2.3 "$source_sha"
  mkdir -p "$test_home/.config/skidbladnir"
  for name in android-signing.p12 android-signing.properties android-signing.password; do
    printf 'preserve %s\n' "$name" >"$test_home/.config/skidbladnir/$name"
    chmod 0600 "$test_home/.config/skidbladnir/$name"
  done
  signing_sha="$({
    for name in android-signing.p12 android-signing.properties android-signing.password; do
      dev_server_sha256 "$test_home/.config/skidbladnir/$name"
    done
  } | dev_server_sha256_stream)"

  skidbladnir_apply arch >"$output"
  current="$(readlink "$test_home/.local/share/skidbladnir/current")"
  [[ "$current" =~ ^releases/v1\.2\.3-[0-9a-f]{64}$ ]] || fail 'current link is not canonical and relative'
  assert_eq '../share/skidbladnir/current/skidbladnir' \
    "$(readlink "$test_home/.local/bin/skidbladnir")" 'binary link'
  [[ ! -e "$test_home/.local/share/skidbladnir/previous" ]] || fail 'fresh install created previous'
  assert_mode 0600 "$test_home/.config/skidbladnir/bearer" 'bearer mode'
  assert_mode 0600 "$test_home/.config/skidbladnir/machine-handle" 'machine-handle mode'
  for name in android-signing.p12 android-signing.properties android-signing.password; do
    assert_mode 0600 "$test_home/.config/skidbladnir/$name" "$name mode"
  done
  assert_mode 0600 "$test_home/.local/state/dev-server/active/skid.runtime.sha256" 'runtime identity mode'
  assert_eq 1 "$(count_calls '^systemctl .* start ')" 'fresh start count'
  assert_eq 0 "$(count_calls '^systemctl .* restart ')" 'fresh restart count'
  assert_eq 1 "$(count_calls '^systemctl .* daemon-reload')" 'fresh unit reload count'
  assert_eq 1 "$(count_calls '^tailscale serve --bg ')" 'fresh Serve mutation count'
  assert_contains "$output" 'STARTED  skid.runtime: v1.2.3' 'fresh activation result'
  inode_before="$(stat -c '%i' "$test_home/.local/share/skidbladnir/current" 2>/dev/null || stat -f '%i' "$test_home/.local/share/skidbladnir/current")"

  stale_stage="$test_home/.local/share/skidbladnir/.apply.stage.Abc123"
  mkdir "$stale_stage"
  printf 'interrupted staging\n' >"$stale_stage/archive.tar.gz"
  : >"$test_calls"
  : >"$output"
  reset_results
  skidbladnir_apply arch >"$output"
  assert_eq 0 "$(count_calls '^systemctl .* start ')" 'second start count'
  assert_eq 0 "$(count_calls '^systemctl .* restart ')" 'second restart count'
  assert_eq 0 "$(count_calls '^systemctl .* daemon-reload')" 'second reload count'
  assert_eq 0 "$(count_calls '^tailscale serve --bg ')" 'second Serve mutation count'
  [[ ! -s "$output" ]] || fail 'second apply emitted a mutation or action'
  assert_eq 0 "$dev_server_result_mutations" 'second apply mutation results'
  assert_eq 0 "$dev_server_result_activations" 'second apply activation results'
  [[ ! -e "$stale_stage" ]] || fail 'interrupted staging was not cleaned on retry'
  assert_eq "$inode_before" \
    "$(stat -c '%i' "$test_home/.local/share/skidbladnir/current" 2>/dev/null || stat -f '%i' "$test_home/.local/share/skidbladnir/current")" \
    'second apply current-link inode'
  assert_eq "$signing_sha" "$({
    for name in android-signing.p12 android-signing.properties android-signing.password; do
      dev_server_sha256 "$test_home/.config/skidbladnir/$name"
    done
  } | dev_server_sha256_stream)" 'Android signing credential preservation'
)

test_admission_failures_preserve_state() (
  local current bearer_sha machine_sha status mode
  local source_one=1111111111111111111111111111111111111111
  local source_two=2222222222222222222222222222222222222222
  setup_case admission
  write_release v1.2.3 "$source_one"
  skidbladnir_apply arch >/dev/null
  current="$(readlink "$test_home/.local/share/skidbladnir/current")"
  bearer_sha="$(dev_server_sha256 "$test_home/.config/skidbladnir/bearer")"
  machine_sha="$(dev_server_sha256 "$test_home/.config/skidbladnir/machine-handle")"

  for mode in checksum extra_member bad_manifest bad_binary; do
    write_release v1.2.4 "$source_two" "$mode"
    if [[ "$mode" == checksum ]]; then
      jq '.artifacts["linux-amd64"].sha256 = ("0" * 64)' \
        "$skidbladnir_release_pin_file" >"$case_dir/pin.next"
      mv "$case_dir/pin.next" "$skidbladnir_release_pin_file"
    fi
    set +e
    (skidbladnir_apply arch) >"$case_dir/$mode.out" 2>&1
    status=$?
    set -e
    ((status != 0)) || fail "$mode admission failure was accepted"
    assert_eq "$current" "$(readlink "$test_home/.local/share/skidbladnir/current")" \
      "$mode current preservation"
    assert_eq "$bearer_sha" "$(dev_server_sha256 "$test_home/.config/skidbladnir/bearer")" \
      "$mode bearer preservation"
    assert_eq "$machine_sha" "$(dev_server_sha256 "$test_home/.config/skidbladnir/machine-handle")" \
      "$mode machine-handle preservation"
  done
)

test_upgrade_integration_and_credentials() (
  local old_current bearer_sha machine_sha output="$fixture/upgrade-output" deployed_unit
  setup_case upgrade
  write_release v1.2.3 1111111111111111111111111111111111111111
  skidbladnir_apply arch >/dev/null
  old_current="$(readlink "$test_home/.local/share/skidbladnir/current")"
  bearer_sha="$(dev_server_sha256 "$test_home/.config/skidbladnir/bearer")"
  machine_sha="$(dev_server_sha256 "$test_home/.config/skidbladnir/machine-handle")"

  write_release v1.2.4 2222222222222222222222222222222222222222
  : >"$test_calls"
  reset_results
  skidbladnir_apply arch >"$output"
  assert_eq 1 "$(count_calls '^systemctl .* restart ')" 'upgrade restart count'
  assert_eq 0 "$(count_calls '^systemctl .* start ')" 'upgrade start count'
  assert_eq 0 "$(count_calls '^systemctl .* daemon-reload')" 'runtime-only unit reload count'
  assert_eq "$old_current" "$(readlink "$test_home/.local/share/skidbladnir/previous")" \
    'upgrade previous pointer'
  assert_eq 2 "$(find "$test_home/.local/share/skidbladnir/releases" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" \
    'retained generation count'
  assert_eq "$bearer_sha" "$(dev_server_sha256 "$test_home/.config/skidbladnir/bearer")" \
    'upgrade bearer preservation'
  assert_eq "$machine_sha" "$(dev_server_sha256 "$test_home/.config/skidbladnir/machine-handle")" \
    'upgrade machine preservation'
  assert_contains "$output" 'RESTARTED  skid.runtime: v1.2.4' 'upgrade activation result'

  printf '\n# integration-only fixture change\n' >>"$case_dir/assets/skidbladnir/skid-notify-linux"
  : >"$test_calls"
  : >"$output"
  reset_results
  skidbladnir_apply arch >"$output"
  has_change skid.integration || fail 'integration-only mutation was not typed'
  assert_eq 0 "$(count_calls '^systemctl .* restart ')" 'integration-only restart count'
  assert_eq 0 "$dev_server_result_activations" 'integration-only activation result count'
  assert_contains "$output" 'CHANGED  skid.integration' 'integration-only result'

  deployed_unit="$test_home/.config/systemd/user/skidbladnir.service"
  printf '\n# observed unit drift\n' >>"$deployed_unit"
  : >"$test_calls"
  : >"$output"
  reset_results
  skidbladnir_apply arch >"$output"
  assert_eq 1 "$(count_calls '^systemctl .* daemon-reload')" 'unit repair reload count'
  assert_eq 1 "$(count_calls '^systemctl .* restart ')" 'unit repair restart count'
  assert_contains "$output" 'CHANGED  skid.unit' 'unit repair result'
)

test_rollback_interruption_and_retry() (
  local old_current candidate status output="$fixture/rollback-output" unit unit_sha
  setup_case rollback
  write_release v1.2.3 1111111111111111111111111111111111111111
  skidbladnir_apply arch >/dev/null
  old_current="$(readlink "$test_home/.local/share/skidbladnir/current")"
  unit="$test_home/.config/systemd/user/skidbladnir.service"
  unit_sha="$(dev_server_sha256 "$unit")"

  write_release v1.2.4 2222222222222222222222222222222222222222
  printf '\n# candidate unit input\n' >>"$case_dir/assets/skidbladnir/skidbladnir.service"
  test_fail_action=restart
  : >"$test_calls"
  set +e
  (skidbladnir_apply arch) >"$output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'failed candidate activation returned success'
  assert_eq "$old_current" "$(readlink "$test_home/.local/share/skidbladnir/current")" \
    'rollback current pointer'
  assert_eq v1.2.3 "$(cat "$test_service_version")" 'rollback running version'
  assert_eq 2 "$(count_calls '^systemctl .* restart ')" 'candidate plus rollback restart count'
  assert_eq 2 "$(count_calls '^systemctl .* daemon-reload')" 'candidate plus rollback reload count'
  assert_eq "$unit_sha" "$(dev_server_sha256 "$unit")" 'rollback unit restoration'
  assert_contains "$output" 'verified prior runtime was restored' 'rollback result'
  candidate="$(find "$test_home/.local/share/skidbladnir/releases" -mindepth 1 -maxdepth 1 -type d -name 'v1.2.4-*' -print -quit)"
  [[ -n "$candidate" ]] || fail 'failed candidate generation was not retained for retry'

  # Model interruption after pointer promotion but before activation identity recording.
  skidbladnir_atomic_symlink "$test_home/.local/share/skidbladnir/previous" \
    "$old_current" generation
  skidbladnir_atomic_symlink "$test_home/.local/share/skidbladnir/current" \
    "releases/$(basename "$candidate")" generation
  atomic_install_file "$case_dir/assets/skidbladnir/skidbladnir.service" "$unit" 0644
  [[ "$(dev_server_sha256 "$unit")" != "$unit_sha" ]] ||
    fail 'interruption fixture did not overwrite the active unit'
  test_reject_version=v1.2.4
  : >"$test_calls"
  set +e
  (skidbladnir_apply arch) >"$case_dir/interrupted-failure-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'persistently failed interrupted candidate returned success'
  assert_eq "$old_current" "$(readlink "$test_home/.local/share/skidbladnir/current")" \
    'interrupted-failure verified current rollback'
  [[ ! -e "$test_home/.local/share/skidbladnir/previous" ]] ||
    fail 'interrupted-failure duplicated the restored current as previous'
  assert_eq v1.2.3 "$(cat "$test_service_version")" \
    'interrupted-failure running rollback version'
  assert_eq "$unit_sha" "$(dev_server_sha256 "$unit")" \
    'interrupted-failure durable unit rollback'
  assert_eq 2 "$(count_calls '^systemctl .* restart ')" \
    'interrupted-failure candidate plus verified rollback restart count'
  assert_contains "$case_dir/interrupted-failure-output" 'verified prior runtime was restored' \
    'interrupted-failure rollback result'

  # Model power loss after restarting the candidate but before health/journal
  # commit, with the candidate now unhealthy and the prior active journal intact.
  skidbladnir_atomic_symlink "$test_home/.local/share/skidbladnir/previous" \
    "$old_current" generation
  skidbladnir_atomic_symlink "$test_home/.local/share/skidbladnir/current" \
    "releases/$(basename "$candidate")" generation
  atomic_install_file "$case_dir/assets/skidbladnir/skidbladnir.service" "$unit" 0644
  printf '%s\n' v0.0.0 >"$test_service_version"
  test_reject_version=''
  : >"$test_calls"
  set +e
  (skidbladnir_apply arch) >"$case_dir/post-restart-interruption-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'unhealthy post-restart interruption returned success'
  assert_eq "$old_current" "$(readlink "$test_home/.local/share/skidbladnir/current")" \
    'post-restart verified current rollback'
  assert_eq v1.2.3 "$(cat "$test_service_version")" \
    'post-restart running rollback version'
  assert_eq "$unit_sha" "$(dev_server_sha256 "$unit")" \
    'post-restart durable unit rollback'
  assert_contains "$case_dir/post-restart-interruption-output" \
    'verified prior runtime was restored' 'post-restart rollback result'

  : >"$test_calls"
  reset_results
  skidbladnir_apply arch >/dev/null
  assert_eq 1 "$(count_calls '^systemctl .* restart ')" 'interrupted retry restart count'
  assert_eq 1 "$(count_calls '^systemctl .* daemon-reload')" 'interrupted retry reload count'
  assert_eq v1.2.4 "$(cat "$test_service_version")" 'interrupted retry running version'
  assert_eq "releases/$(basename "$candidate")" \
    "$(readlink "$test_home/.local/share/skidbladnir/current")" 'interrupted retry pointer'
)

test_interrupted_first_install_remains_unreferenced() (
  local candidate status unit

  setup_case first-interruption
  write_release v1.2.3 1111111111111111111111111111111111111111
  test_fail_action=start
  set +e
  (skidbladnir_apply arch) >"$case_dir/provision-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'first-interruption fixture unexpectedly activated'
  candidate="$(find "$test_home/.local/share/skidbladnir/releases" \
    -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$candidate" ]] || fail 'first-interruption candidate is missing'

  # Model an uncatchable stop after file/pointer promotion but before first
  # activation and active-identity recording.
  unit="$test_home/.config/systemd/user/skidbladnir.service"
  atomic_install_file "$case_dir/assets/skidbladnir/skidbladnir-launch" \
    "$test_home/.local/bin/skidbladnir-launch" 0755
  atomic_install_file "$case_dir/assets/skidbladnir/skidbladnir.service" "$unit" 0644
  skidbladnir_atomic_symlink "$test_home/.local/share/skidbladnir/current" \
    "releases/$(basename "$candidate")" generation
  skidbladnir_atomic_symlink "$test_home/.local/bin/skidbladnir" \
    '../share/skidbladnir/current/skidbladnir' binary
  : >"$test_service_enabled"
  test_fail_action=''
  test_reject_version=v1.2.3
  : >"$test_calls"
  set +e
  (skidbladnir_apply arch) >"$case_dir/retry-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'interrupted first candidate unexpectedly activated'
  [[ ! -e "$test_service_active" ]] || fail 'interrupted first service remains active'
  [[ ! -e "$test_service_enabled" ]] || fail 'interrupted first service remains enabled'
  [[ ! -e "$test_home/.local/share/skidbladnir/current" ]] ||
    fail 'interrupted first candidate remains referenced'
  [[ ! -e "$test_home/.local/bin/skidbladnir" ]] ||
    fail 'interrupted first binary link remains installed'
  [[ ! -e "$test_home/.local/bin/skidbladnir-launch" ]] ||
    fail 'interrupted first launcher remains installed'
  [[ ! -e "$unit" ]] || fail 'interrupted first unit remains installed'
  assert_contains "$case_dir/retry-output" \
    'first activation failed; the candidate is inactive and unreferenced' \
    'interrupted first rollback result'
)

test_unjournaled_unhealthy_first_activation_is_removed() (
  local status

  setup_case first-active-interruption
  write_release v1.2.3 1111111111111111111111111111111111111111
  skidbladnir_apply arch >/dev/null
  rm -f -- \
    "$test_home/.local/state/dev-server/active/skid.runtime.sha256" \
    "$test_home/.local/state/dev-server/active/skid.unit.sha256"
  printf '%s\n' v0.0.0 >"$test_service_version"
  : >"$test_calls"
  set +e
  (skidbladnir_apply arch) >"$case_dir/retry-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'unjournaled unhealthy first activation returned success'
  if [[ -e "$test_service_active" ]]; then
    cat "$case_dir/retry-output" >&2
    fail 'unjournaled unhealthy service remains active'
  fi
  [[ ! -e "$test_service_enabled" ]] || fail 'unjournaled unhealthy service remains enabled'
  [[ ! -e "$test_home/.local/share/skidbladnir/current" ]] ||
    fail 'unjournaled unhealthy runtime remains referenced'
  [[ ! -e "$test_home/.local/bin/skidbladnir" ]] ||
    fail 'unjournaled unhealthy binary remains installed'
  [[ ! -e "$test_home/.local/bin/skidbladnir-launch" ]] ||
    fail 'unjournaled unhealthy launcher remains installed'
  [[ ! -e "$test_home/.config/systemd/user/skidbladnir.service" ]] ||
    fail 'unjournaled unhealthy unit remains installed'
  assert_contains "$case_dir/retry-output" \
    'unverified Skidbladnir first activation was stopped and unreferenced' \
    'unjournaled unhealthy rollback result'
)

test_first_failure_is_inactive_and_unreferenced() (
  local candidate status
  setup_case first-failure
  write_release v1.2.3 1111111111111111111111111111111111111111
  test_fail_action=start
  set +e
  (skidbladnir_apply arch) >"$case_dir/failure-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'first activation failure returned success'
  [[ ! -e "$test_service_active" ]] || fail 'failed first service remains active'
  [[ ! -e "$test_service_enabled" ]] || fail 'failed first service remains enabled'
  [[ ! -e "$test_home/.local/share/skidbladnir/current" ]] || fail 'failed first candidate remains current'
  [[ ! -e "$test_home/.local/bin/skidbladnir" ]] || fail 'failed first binary link remains installed'
  [[ ! -e "$test_home/.config/systemd/user/skidbladnir.service" ]] || fail 'failed first unit remains installed'
  candidate="$(find "$test_home/.local/share/skidbladnir/releases" -mindepth 1 -maxdepth 1 -type d -print -quit)"
  [[ -n "$candidate" ]] || fail 'failed first candidate was not retained'
  skidbladnir_secret_valid "$test_home/.config/skidbladnir/bearer" \
    '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || fail 'minted bearer was not preserved safely'
  assert_eq 1 "$(count_calls '^systemctl .* disable ')" 'first-failure enablement rollback count'

  : >"$test_calls"
  reset_results
  skidbladnir_apply arch >/dev/null
  assert_eq 1 "$(count_calls '^systemctl .* start ')" 'first-failure retry start count'
  [[ -L "$test_home/.local/share/skidbladnir/current" ]] || fail 'retry did not reference candidate'
)

test_credentials_and_protected_symlinks_fail_closed() (
  local referent status current unexpected
  setup_case symlinks
  write_release v1.2.3 1111111111111111111111111111111111111111
  mkdir -p "$test_home/.config/skidbladnir"
  referent="$case_dir/referent"
  printf 'preserve\n' >"$referent"
  ln -s "$referent" "$test_home/.config/skidbladnir/bearer"
  set +e
  (skidbladnir_apply arch) >"$case_dir/symlink-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'symlinked credential was accepted'
  assert_eq preserve "$(tr -d '\n' <"$referent")" 'symlink referent preservation'

  rm "$test_home/.config/skidbladnir/bearer"
  skidbladnir_apply arch >/dev/null
  current="$(readlink "$test_home/.local/share/skidbladnir/current")"
  printf 'legacy flat release\n' >"$test_home/.local/share/skidbladnir/release.json"
  set +e
  (skidbladnir_apply arch) >"$case_dir/legacy-state-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'legacy flat release state was accepted'
  assert_eq "$current" "$(readlink "$test_home/.local/share/skidbladnir/current")" \
    'legacy-state current preservation'
  rm "$test_home/.local/share/skidbladnir/release.json"

  unexpected="$test_home/.local/share/skidbladnir/releases/v9.9.9-$(printf '%064d' 0)"
  ln -s "$case_dir" "$unexpected"
  set +e
  (skidbladnir_apply arch) >"$case_dir/generation-symlink-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'unexpected release symlink was accepted'
  [[ -L "$unexpected" ]] || fail 'unexpected release symlink was followed or replaced'
  rm "$unexpected"

  chmod 0644 "$test_home/.config/skidbladnir/bearer"
  set +e
  (skidbladnir_apply arch) >"$case_dir/mode-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'wrong credential mode was repaired instead of rejected'
  assert_eq "$current" "$(readlink "$test_home/.local/share/skidbladnir/current")" \
    'credential-mode current preservation'
  chmod 0600 "$test_home/.config/skidbladnir/bearer"

  printf 'preserve signing password\n' >"$test_home/.config/skidbladnir/android-signing.password"
  chmod 0644 "$test_home/.config/skidbladnir/android-signing.password"
  set +e
  (skidbladnir_apply arch) >"$case_dir/signing-mode-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'wrong Android signing credential mode was accepted'
  assert_eq 'preserve signing password' \
    "$(tr -d '\n' <"$test_home/.config/skidbladnir/android-signing.password")" \
    'Android signing credential preservation'
  chmod 0600 "$test_home/.config/skidbladnir/android-signing.password"

  rm "$test_home/.local/share/skidbladnir/current"
  printf 'not a link\n' >"$test_home/.local/share/skidbladnir/current"
  set +e
  (skidbladnir_apply arch) >"$case_dir/current-output" 2>&1
  status=$?
  set -e
  ((status != 0)) || fail 'regular current pointer was accepted'
  assert_eq 'not a link' "$(tr -d '\n' <"$test_home/.local/share/skidbladnir/current")" \
    'protected current preservation'
)

test_private_serve_actions_and_public_failure() (
  local output="$fixture/serve-output" status
  setup_case serve
  write_release v1.2.3 1111111111111111111111111111111111111111
  skidbladnir_apply arch >/dev/null

  printf '%s\n' \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"stale.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}}}' \
    >"$SKID_TEST_SERVE_STATUS"
  reset_results
  : >"$test_calls"
  skidbladnir_reconcile_serve >"$output"
  assert_eq 1 "$dev_server_result_actions" 'stale Serve action count'
  assert_eq 0 "$(count_calls '^tailscale serve --bg ')" 'stale Serve automatic mutation count'
  assert_eq \
    "ACTION  tailscale.serve: remove the stale HTTPS 8443 mapping with 'tailscale serve --https=8443 off', then rerun apply" \
    "$(cat "$output")" 'stale Serve exact action'
  set +e
  finish_results arch >/dev/null
  status=$?
  set -e
  assert_eq 2 "$status" 'stale Serve summary exit'

  printf '%s\n' \
    '{"TCP":{"8443":{"HTTPS":true}},"Web":{"test.example.ts.net:8443":{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}},"AllowFunnel":{"test.example.ts.net:8443":true}}' \
    >"$SKID_TEST_SERVE_STATUS"
  set +e
  skidbladnir_reconcile_serve >/dev/null
  status=$?
  set -e
  assert_eq 3 "$status" 'public Serve rejection status'
)

test_macos_exact_service_lifecycle() (
  local loaded pending running launchd_disabled_marker

  setup_case macos-service
  loaded="$case_dir/launchd-loaded"
  pending="$case_dir/launchd-pending"
  running="$case_dir/launchd-running"
  launchd_disabled_marker="$case_dir/launchd-disabled"
  launchctl() {
    printf 'launchctl' >>"$test_calls"
    printf ' %q' "$@" >>"$test_calls"
    printf '\n' >>"$test_calls"
    case "${1:-}" in
    print-disabled)
      printf '%s\n' 'disabled services = {'
      if [[ -f "$launchd_disabled_marker" ]]; then
        printf '%s\n' '    "dev.niels.skidbladnir" => disabled'
      else
        printf '%s\n' '    "dev.niels.skidbladnir" => enabled'
      fi
      printf '%s\n' '}'
      ;;
    print)
      [[ -f "$loaded" ]] || return 113
      if [[ -f "$pending" ]]; then
        mv "$pending" "$running"
        printf '\tstate = spawn scheduled\n'
      elif [[ -f "$running" ]]; then
        printf '\tstate = running\n'
      else
        printf '\tstate = exited\n'
      fi
      printf '\tresource coalition = {\n\t\tstate = active\n\t}\n'
      printf '\tjetsam coalition = {\n\t\tstate = active\n\t}\n'
      ;;
    enable) rm -f -- "$launchd_disabled_marker" ;;
    disable) : >"$launchd_disabled_marker" ;;
    bootstrap | kickstart)
      : >"$loaded"
      rm -f -- "$running"
      : >"$pending"
      ;;
    bootout)
      rm -f -- "$loaded" "$pending" "$running"
      ;;
    *) return 64 ;;
    esac
  }

  : >"$launchd_disabled_marker"
  skidbladnir_activate_service macos "$test_home" 0 1 1
  assert_eq STARTED "$skidbladnir_activation_status" 'macOS first activation status'
  assert_eq 1 "$skidbladnir_enablement_changed" 'macOS enablement change'
  assert_eq 1 "$(count_calls '^launchctl enable ')" 'macOS enable count'
  assert_eq 1 "$(count_calls '^launchctl bootstrap ')" 'macOS bootstrap count'
  sleep() { :; }
  skidbladnir_wait_for_active macos || fail 'macOS delayed service was not observed running'

  : >"$test_calls"
  skidbladnir_activate_service macos "$test_home" 1 0 0
  assert_eq '' "$skidbladnir_activation_status" 'macOS no-op activation status'
  assert_eq 0 "$(count_calls '^launchctl (enable|bootstrap|bootout|kickstart) ')" \
    'macOS no-op mutation count'

  : >"$test_calls"
  skidbladnir_activate_service macos "$test_home" 1 1 1
  assert_eq RESTARTED "$skidbladnir_activation_status" 'macOS unit restart status'
  assert_eq 1 "$(count_calls '^launchctl bootout ')" 'macOS unit bootout count'
  assert_eq 1 "$(count_calls '^launchctl bootstrap ')" 'macOS unit bootstrap count'

  : >"$test_calls"
  skidbladnir_activate_service macos "$test_home" 1 1 0
  assert_eq 1 "$(count_calls '^launchctl kickstart .*dev\.niels\.skidbladnir$')" \
    'macOS runtime kickstart count'

  rm -f -- "$pending" "$running"
  : >"$test_calls"
  skidbladnir_activate_service macos "$test_home" 0 1 0
  assert_eq STARTED "$skidbladnir_activation_status" 'macOS loaded-stopped start status'
  assert_eq 1 "$(count_calls '^launchctl kickstart ')" 'macOS loaded-stopped kickstart count'
  assert_eq 0 "$(count_calls '^launchctl bootstrap ')" 'macOS loaded-stopped bootstrap count'
)

test_service_observation_errors_are_read_only() (
  local status

  setup_case service-observation-error
  write_release v1.2.3 1111111111111111111111111111111111111111
  systemctl() { return 4; }
  set +e
  (skidbladnir_apply arch) >/dev/null 2>&1
  status=$?
  set -e
  assert_eq 1 "$status" 'systemd observation error apply status'
  [[ ! -e "$test_home/.local/share/skidbladnir" ]] ||
    fail 'systemd observation error mutated Skidbladnir state'
  assert_eq 0 "$(count_calls '^download ')" \
    'systemd observation error download count'

  launchctl() {
    [[ "${1:-}" == print ]] || return 64
    printf '%s\n' 'malformed launchd response'
  }
  set +e
  skidbladnir_service_active macos
  status=$?
  set -e
  assert_eq 2 "$status" 'malformed launchd observation status'
)

test_forbidden_residue_and_layout() (
  local path
  for path in skidbladnir lib/skidbladnir-invite.sh lib/skidbladnir-operator.sh; do
    [[ ! -e "$repo_dir/$path" ]] || fail "removed production path remains: $path"
  done
  if grep -Ern \
    'skidbladnir_(doctor|converge)|release-transaction|release-activation-required|LocalAPI|localapi/v|dangerously-bypass-approvals-and-sandbox|permission-mode.*auto' \
    "$repo_dir/lib/skidbladnir.sh" "$repo_dir/assets/skidbladnir" >"$fixture/residue"; then
    cat "$fixture/residue" >&2
    fail 'forbidden Skidbladnir production residue remains'
  fi
  assert_contains "$repo_dir/assets/skidbladnir/skidbladnir.service" \
    '.local/share/skidbladnir/current/characters.json' 'systemd current catalogue path'
  assert_contains "$repo_dir/assets/skidbladnir/skidbladnir.service" \
    '.local/share/skidbladnir/current/host-config.json' 'systemd current host-config path'
)

run_test() {
  "$1"
  tests_run=$((tests_run + 1))
}

run_test test_pin_and_config_contract
run_test test_platform_scoped_declared_inputs
run_test test_fresh_noop_and_exact_activation
run_test test_admission_failures_preserve_state
run_test test_upgrade_integration_and_credentials
run_test test_rollback_interruption_and_retry
run_test test_first_failure_is_inactive_and_unreferenced
run_test test_interrupted_first_install_remains_unreferenced
run_test test_unjournaled_unhealthy_first_activation_is_removed
run_test test_credentials_and_protected_symlinks_fail_closed
run_test test_private_serve_actions_and_public_failure
run_test test_macos_exact_service_lifecycle
run_test test_service_observation_errors_are_read_only
run_test test_forbidden_residue_and_layout

printf 'skidbladnir: %d contract tests passed\n' "$tests_run"
