#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
: "${skidbladnir_release_pin_file:=$dev_server_root/assets/skidbladnir/release-pin.json}"

skidbladnir_release_values() {
  local platform="$1"
  local digest_field
  local pin_bytes
  local observed_keys
  case "$platform" in
  devbox | arch) digest_field=linuxAmd64Sha256 ;;
  macos) digest_field=darwinArm64Sha256 ;;
  *) die "unsupported Skidbladnir platform: $platform" ;;
  esac

  [[ -f "$skidbladnir_release_pin_file" && ! -L "$skidbladnir_release_pin_file" ]] || return 1
  pin_bytes="$(LC_ALL=C wc -c <"$skidbladnir_release_pin_file" | tr -d '[:space:]')"
  [[ "$pin_bytes" =~ ^[1-9][0-9]{0,3}$ && "$pin_bytes" -le 4096 ]] || return 1
  observed_keys="$(
    jq --stream -er \
      'select(length == 2 and (.[0] | length) == 1) | .[0][0]' \
      "$skidbladnir_release_pin_file" | LC_ALL=C sort
  )" || return 1
  [[ "$observed_keys" == $'androidApkSha256\nandroidSigningCertAssetSha256\ndarwinArm64Sha256\nlinuxAmd64Sha256\nsha256SumsAssetSha256\nsourceSha\nversion' ]] || return 1

  jq -er --arg digest_field "$digest_field" '
    if type == "object" and
      (keys == ["androidApkSha256", "androidSigningCertAssetSha256", "darwinArm64Sha256", "linuxAmd64Sha256", "sha256SumsAssetSha256", "sourceSha", "version"]) and
      (.version | type == "string" and test("^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$")) and
      ((.version | capture("^v(?<major>0|[1-9][0-9]*)\\.(?<minor>0|[1-9][0-9]*)\\.(?<patch>0|[1-9][0-9]*)$")) as $semver |
        ($semver.major | length) <= 4 and
        ($semver.minor | length) <= 3 and
        ($semver.patch | length) <= 3 and
        ($semver.major | tonumber) <= 2100 and
        ((($semver.major | tonumber) * 1000000) +
          (($semver.minor | tonumber) * 1000) +
          ($semver.patch | tonumber)) > 1 and
        ((($semver.major | tonumber) * 1000000) +
          (($semver.minor | tonumber) * 1000) +
          ($semver.patch | tonumber)) <= 2100000000) and
      (.sourceSha | type == "string" and test("^[0-9a-f]{40}$")) and
      (.androidApkSha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.androidSigningCertAssetSha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.linuxAmd64Sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.darwinArm64Sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
      (.sha256SumsAssetSha256 | type == "string" and test("^[0-9a-f]{64}$"))
    then [.version, .sourceSha, .[$digest_field]] | @tsv
    else error("release pin is pending or invalid")
    end
  ' "$skidbladnir_release_pin_file"
}

skidbladnir_asset_name() {
  case "$1" in
  devbox | arch) printf 'skidbladnir-linux-amd64.tar.gz\n' ;;
  macos) printf 'skidbladnir-darwin-arm64.tar.gz\n' ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_manifest_platform() {
  case "$1" in
  devbox | arch) printf 'linux-amd64\n' ;;
  macos) printf 'darwin-arm64\n' ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_host_config_source() {
  case "$1" in
  devbox) printf '%s/assets/skidbladnir/host-config-devbox.json\n' "$dev_server_root" ;;
  arch) printf '%s/assets/skidbladnir/host-config-arch.json\n' "$dev_server_root" ;;
  macos) printf '%s/assets/skidbladnir/host-config-macbook.json\n' "$dev_server_root" ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_preflight_tmux_runtime() {
  local platform="$1"
  local config tmux_path tmux_version
  config="$(skidbladnir_host_config_source "$platform")"
  tmux_path="$(jq -er '.tmux.path' "$config")" || die "Skidbladnir tmux path is invalid"
  tmux_version="$(jq -er '.tmux.version' "$config")" || die "Skidbladnir tmux version is invalid"
  if [[ -e "$tmux_path" || -L "$tmux_path" ]]; then
    [[ -x "$tmux_path" &&
      "$($tmux_path -V 2>/dev/null || true)" == "$tmux_version" ]] ||
      die "Installed tmux differs from the exact Skidbladnir host-config version; resolve it before convergence"
  fi
}

skidbladnir_require_tmux_runtime() {
  local platform="$1"
  local config tmux_path tmux_version
  config="$(skidbladnir_host_config_source "$platform")"
  tmux_path="$(jq -er '.tmux.path' "$config")" || die "Skidbladnir tmux path is invalid"
  tmux_version="$(jq -er '.tmux.version' "$config")" || die "Skidbladnir tmux version is invalid"
  [[ -x "$tmux_path" &&
    "$($tmux_path -V 2>/dev/null || true)" == "$tmux_version" ]] ||
    die "Package convergence did not produce the exact Skidbladnir tmux version"
}

skidbladnir_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

skidbladnir_sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

skidbladnir_archive_member_sha256() (
  set -o pipefail
  tar -xOzf "$1" "$2" | skidbladnir_sha256_stream
)

skidbladnir_file_mode() {
  case "$(uname -s)" in
  Darwin) stat -f '%Lp' "$1" ;;
  *) stat -c '%a' "$1" ;;
  esac
}

skidbladnir_secret_valid() (
  set +x
  local path="$1"
  local pattern="$2"
  local value framed
  [[ -f "$path" && ! -L "$path" && "$(skidbladnir_file_mode "$path" 2>/dev/null)" == 600 ]] || return 1
  value="$(cat "$path")" || return 1
  framed="$(
    cat "$path"
    printf .
  )" || return 1
  [[ "$framed" == "$value"$'\n.' && "$value" =~ $pattern ]]
)

skidbladnir_authenticated_loopback() (
  set +x
  local config_dir="$1"
  local endpoint="$2"
  local url
  case "$endpoint" in
  pressure) url='http://127.0.0.1:7341/v1/pressure' ;;
  sessions) url='http://127.0.0.1:7341/v1/sessions' ;;
  *) return 64 ;;
  esac
  skidbladnir_secret_valid "$config_dir/machine-handle" '^mh-[0-9a-f]{32}$' || return 1
  skidbladnir_secret_valid "$config_dir/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || return 1
  {
    printf 'silent\nshow-error\nfail\nconnect-timeout = 2\nmax-time = 5\n'
    printf 'header = "Authorization: Bearer %s"\n' "$(cat "$config_dir/bearer")"
    printf 'header = "Skidbladnir-Machine: %s"\n' "$(cat "$config_dir/machine-handle")"
    printf 'url = "%s"\n' "$url"
  } | curl -q --noproxy '*' --config -
)

skidbladnir_install_owned() {
  local source="$1"
  local target="$2"
  local mode="$3"
  local expected_mode="${mode#0}"
  local target_dir
  local target_name
  local temporary
  [[ -f "$source" && ! -L "$source" ]] || die "Skidbladnir owned source is not a regular file: $source"
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -f "$target" && ! -L "$target" ]] ||
      die "Skidbladnir owned target is not a regular file: $target"
  fi
  if [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target" &&
    [[ "$(skidbladnir_file_mode "$target")" == "$expected_mode" ]]; then
    return
  fi
  target_dir="$(dirname "$target")"
  target_name="$(basename "$target")"
  temporary="$(mktemp "$target_dir/.$target_name.skidbladnir.XXXXXX")"
  if ! install -m "$mode" "$source" "$temporary" ||
    ! cmp -s "$source" "$temporary" ||
    [[ "$(skidbladnir_file_mode "$temporary" 2>/dev/null)" != "$expected_mode" ]]; then
    rm -f -- "$temporary"
    die "Could not stage Skidbladnir owned target: $target"
  fi
  if ! mv -f -- "$temporary" "$target"; then
    rm -f -- "$temporary"
    die "Could not promote Skidbladnir owned target: $target"
  fi
  [[ -f "$target" && ! -L "$target" ]] && cmp -s "$source" "$target" &&
    [[ "$(skidbladnir_file_mode "$target" 2>/dev/null)" == "$expected_mode" ]] ||
    die "Promoted Skidbladnir owned target failed verification: $target"
  skidbladnir_changed=1
}

skidbladnir_release_transaction_remove() {
  local share_dir="$1"
  local transaction="$share_dir/.release-transaction"
  [[ -d "$transaction" && ! -L "$transaction" ]] ||
    die "Skidbladnir release transaction is not a private directory"
  rm -R -- "$transaction"
}

skidbladnir_release_transaction_snapshot() {
  local target="$1"
  local backup="$2"
  local expected_mode="$3"
  if [[ -e "$target" || -L "$target" ]]; then
    [[ -f "$target" && ! -L "$target" ]] ||
      die "Skidbladnir release target is not a regular file: $target"
    install -m "$expected_mode" "$target" "$backup"
    cmp -s "$target" "$backup" || die "Could not snapshot Skidbladnir release target: $target"
    : >"$backup.present"
  else
    : >"$backup.absent"
  fi
}

skidbladnir_release_transaction_restore() {
  local target="$1"
  local backup="$2"
  local mode="$3"
  if [[ -f "$backup.present" && ! -L "$backup.present" &&
    ! -e "$backup.absent" && ! -L "$backup.absent" ]]; then
    [[ -f "$backup" && ! -L "$backup" ]] ||
      die "Skidbladnir release transaction backup is missing: $backup"
    skidbladnir_install_owned "$backup" "$target" "$mode"
    cmp -s "$backup" "$target" || die "Could not restore Skidbladnir release target: $target"
  elif [[ -f "$backup.absent" && ! -L "$backup.absent" &&
    ! -e "$backup.present" && ! -L "$backup.present" ]]; then
    if [[ -e "$target" || -L "$target" ]]; then
      [[ -f "$target" && ! -L "$target" ]] ||
        die "Skidbladnir release rollback target is not a regular file: $target"
      /bin/unlink "$target"
      skidbladnir_changed=1
    fi
  else
    die "Skidbladnir release transaction marker is invalid: $backup"
  fi
}

skidbladnir_recover_release_transaction() {
  local home="$1"
  local share_dir="$2"
  local transaction="$share_dir/.release-transaction"
  local state temporary_state
  if [[ ! -e "$transaction" && ! -L "$transaction" ]]; then
    return
  fi
  [[ -d "$transaction" && ! -L "$transaction" &&
    "$(skidbladnir_file_mode "$transaction" 2>/dev/null)" == 700 ]] ||
    die "Skidbladnir release transaction boundary is invalid"
  state="$(cat "$transaction/state" 2>/dev/null || true)"
  if [[ "$state" == preparing ]]; then
    skidbladnir_release_transaction_remove "$share_dir"
    return
  fi
  [[ "$state" == prepared || "$state" == recovering ]] ||
    die "Skidbladnir release transaction state is invalid"
  temporary_state="$transaction/.state.recovering"
  printf 'recovering\n' >"$temporary_state"
  mv -f -- "$temporary_state" "$transaction/state"
  skidbladnir_release_transaction_restore \
    "$home/.local/bin/skidbladnir" "$transaction/binary" 0755
  skidbladnir_release_transaction_restore \
    "$share_dir/characters.json" "$transaction/characters" 0644
  skidbladnir_release_transaction_restore \
    "$share_dir/release.json" "$transaction/manifest" 0644
  skidbladnir_release_transaction_restore \
    "$share_dir/release-bundle.tar.gz" "$transaction/bundle" 0644
  skidbladnir_release_transaction_remove "$share_dir"
}

skidbladnir_begin_release_transaction() {
  local home="$1"
  local share_dir="$2"
  local transaction="$share_dir/.release-transaction"
  local prepared_state
  [[ ! -e "$transaction" && ! -L "$transaction" ]] ||
    die "Skidbladnir release transaction already exists"
  install -d -m 0700 "$transaction"
  printf 'preparing\n' >"$transaction/state"
  skidbladnir_release_transaction_snapshot \
    "$home/.local/bin/skidbladnir" "$transaction/binary" 0755
  skidbladnir_release_transaction_snapshot \
    "$share_dir/characters.json" "$transaction/characters" 0644
  skidbladnir_release_transaction_snapshot \
    "$share_dir/release.json" "$transaction/manifest" 0644
  skidbladnir_release_transaction_snapshot \
    "$share_dir/release-bundle.tar.gz" "$transaction/bundle" 0644
  prepared_state="$transaction/.state.prepared"
  printf 'prepared\n' >"$prepared_state"
  mv -f -- "$prepared_state" "$transaction/state"
}

skidbladnir_commit_release_transaction() {
  local home="$1"
  local share_dir="$2"
  local binary_source="$3"
  local catalogue_source="$4"
  local manifest_source="$5"
  local bundle_source="$6"
  cmp -s "$binary_source" "$home/.local/bin/skidbladnir" &&
    cmp -s "$catalogue_source" "$share_dir/characters.json" &&
    cmp -s "$manifest_source" "$share_dir/release.json" &&
    cmp -s "$bundle_source" "$share_dir/release-bundle.tar.gz" ||
    die "Skidbladnir promoted release tuple failed verification"
  skidbladnir_release_transaction_remove "$share_dir"
}

# shellcheck disable=SC2329 # Invoked indirectly by the converge EXIT trap.
skidbladnir_converge_cleanup() {
  local converge_exit=$?
  trap - EXIT
  if [[ "${release_transaction_active:-0}" == 1 ]]; then
    if ! skidbladnir_recover_release_transaction "$home" "$share_dir"; then
      printf 'Could not restore the prior Skidbladnir release tuple\n' >&2
      converge_exit=1
    fi
  fi
  rm -R -- "$staging" || converge_exit=1
  exit "$converge_exit"
}

skidbladnir_configure_codex_notify() {
  local home="$1"
  local notify="$home/.local/bin/skid-notify"
  local desired="notify = [\"$notify\"]"
  local context config temporary
  for context in personal work work2; do
    config="$home/.codex-$context/config.toml"
    install -d -m 0700 "$(dirname "$config")"
    if [[ -e "$config" || -L "$config" ]]; then
      [[ -f "$config" && ! -L "$config" ]] || die "Codex config is not a regular file: $config"
      if [[ "$(grep -Fxc "$desired" "$config" || true)" == 1 &&
      "$(grep -Ec '^[[:space:]]*notify[[:space:]]*=' "$config" || true)" == 1 ]]; then
        if [[ "$(skidbladnir_file_mode "$config" 2>/dev/null)" != 600 ]]; then
          chmod 0600 "$config"
          skidbladnir_changed=1
        fi
        continue
      fi
      if grep -Eq '^[[:space:]]*notify[[:space:]]*=' "$config"; then
        die "Codex notify configuration conflicts: $config"
      fi
    fi
    temporary="$(mktemp "$(dirname "$config")/.config.toml.skidbladnir.XXXXXX")"
    {
      printf '%s\n' "$desired"
      [[ ! -f "$config" ]] || cat "$config"
    } >"$temporary"
    install -m 0600 "$temporary" "$config"
    rm -f -- "$temporary"
    skidbladnir_changed=1
  done
}

skidbladnir_owned_config_matches() {
  local platform="$1"
  local home="$2"
  local config_source hooks_source notify_source context codex_config desired
  config_source="$(skidbladnir_host_config_source "$platform")"
  [[ -f "$home/.config/skidbladnir/host-config.json" &&
    ! -L "$home/.config/skidbladnir/host-config.json" ]] &&
    cmp -s "$config_source" "$home/.config/skidbladnir/host-config.json" &&
    [[ "$(skidbladnir_file_mode "$home/.config/skidbladnir/host-config.json" 2>/dev/null)" == 600 ]] || return 1
  if [[ "$platform" == macos ]]; then
    hooks_source="$dev_server_root/assets/skidbladnir/status-hooks-macbook.json"
    notify_source="$dev_server_root/assets/skidbladnir/skid-notify-macbook"
  else
    hooks_source="$dev_server_root/assets/skidbladnir/status-hooks-linux.json"
    notify_source="$dev_server_root/assets/skidbladnir/skid-notify-linux"
  fi
  [[ -f "$home/.local/bin/skidbladnir-launch" && ! -L "$home/.local/bin/skidbladnir-launch" ]] &&
    cmp -s "$dev_server_root/assets/skidbladnir/skidbladnir-launch" \
      "$home/.local/bin/skidbladnir-launch" &&
    [[ "$(skidbladnir_file_mode "$home/.local/bin/skidbladnir-launch" 2>/dev/null)" == 755 ]] || return 1
  [[ -f "$home/.local/bin/skid-notify" && ! -L "$home/.local/bin/skid-notify" ]] &&
    cmp -s "$notify_source" "$home/.local/bin/skid-notify" &&
    [[ "$(skidbladnir_file_mode "$home/.local/bin/skid-notify" 2>/dev/null)" == 755 ]] || return 1
  desired="notify = [\"$home/.local/bin/skid-notify\"]"
  for context in personal work work2; do
    [[ -f "$home/.codex-$context/hooks.json" && ! -L "$home/.codex-$context/hooks.json" ]] &&
      cmp -s "$hooks_source" "$home/.codex-$context/hooks.json" &&
      [[ "$(skidbladnir_file_mode "$home/.codex-$context/hooks.json" 2>/dev/null)" == 600 ]] || return 1
    codex_config="$home/.codex-$context/config.toml"
    [[ -f "$codex_config" && ! -L "$codex_config" ]] &&
      [[ "$(skidbladnir_file_mode "$codex_config" 2>/dev/null)" == 600 ]] &&
      [[ "$(grep -Fxc "$desired" "$codex_config" || true)" == 1 ]] &&
      [[ "$(grep -Ec '^[[:space:]]*notify[[:space:]]*=' "$codex_config" || true)" == 1 ]] || return 1
  done
}

skidbladnir_tailscale_cli() {
  if declare -F packages_macos_tailscale_cli >/dev/null; then
    packages_macos_tailscale_cli
  elif command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
  else
    return 1
  fi
}

skidbladnir_configure_serve() {
  local tailscale_cli="$1"
  local serve_status
  if ! TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null |
    jq -e '.BackendState == "Running"' >/dev/null; then
    warn "Skidbladnir Serve pending; sign in to Tailscale, then converge again"
    return
  fi
  serve_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" serve status --json 2>/dev/null)" ||
    die "Skidbladnir Serve status is unavailable"
  printf '%s' "$serve_status" | jq -e '
    type == "object" and
    ((.Web // {}) | type == "object") and
    ([((.Web // {}) | to_entries[]) |
      select(.key | endswith(":8443")) |
      ((.value.Handlers // {}) | keys[]) |
      select(. != "/" and . != "/v1")] | length == 0)
  ' >/dev/null || die "Skidbladnir Serve 8443 has an unowned path; remove it explicitly"

  if printf '%s' "$serve_status" | jq -e '
    [((.Web // {}) | to_entries[]) |
      select(.key | endswith(":8443")) |
      .value.Handlers["/"] |
      select(. != null)] | length > 0
  ' >/dev/null; then
    printf '%s' "$serve_status" | jq -e '
      [((.Web // {}) | to_entries[]) |
        select(.key | endswith(":8443")) |
        .value.Handlers["/"] |
        select(. != null)] == [{"Proxy":"http://127.0.0.1:7341"}]
    ' >/dev/null || die "Skidbladnir Serve root path is not the retired owned mapping"
    # Retired owned command: tailscale serve --yes --https=8443 --set-path=/ off
    TAILSCALE_BE_CLI=1 "$tailscale_cli" serve --yes --https=8443 --set-path=/ off >/dev/null
  fi

  # Desired command: tailscale serve --bg --yes --https=8443 --set-path=/v1 http://127.0.0.1:7341/v1
  TAILSCALE_BE_CLI=1 "$tailscale_cli" serve --bg --yes --https=8443 --set-path=/v1 http://127.0.0.1:7341/v1 >/dev/null
}

skidbladnir_install_linux_service() {
  local home="$1"
  local unit_source="$dev_server_root/assets/skidbladnir/skidbladnir.service"
  local unit_target="$home/.config/systemd/user/skidbladnir.service"
  local was_active=0
  install -d -m 0755 "$(dirname "$unit_target")"
  systemctl --user is-active --quiet skidbladnir.service && was_active=1
  skidbladnir_install_owned "$unit_source" "$unit_target" 0644
  if [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" != yes ]]; then
    sudo loginctl enable-linger "$(id -un)"
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now skidbladnir.service
  if ((was_active && skidbladnir_changed)); then
    systemctl --user restart skidbladnir.service
  fi
}

skidbladnir_install_macos_service() {
  local home="$1"
  local label=dev.niels.skidbladnir
  local domain
  local source="$dev_server_root/assets/skidbladnir/$label.plist"
  local target="$home/Library/LaunchAgents/$label.plist"
  local was_loaded=0
  domain="gui/$(id -u)"
  launchctl print "$domain/$label" >/dev/null 2>&1 && was_loaded=1
  install -d -m 0755 "$(dirname "$target")"
  skidbladnir_install_owned "$source" "$target" 0644
  launchctl enable "$domain/$label"
  if ((was_loaded && skidbladnir_changed)); then
    launchctl bootout "$domain/$label"
    launchctl bootstrap "$domain" "$target"
  elif ((was_loaded)); then
    launchctl kickstart "$domain/$label"
  elif ((!was_loaded)); then
    launchctl bootstrap "$domain" "$target"
  fi
}

skidbladnir_doctor_pass() {
  printf 'PASS  %-28s %s\n' "$1" "$2"
}

skidbladnir_doctor_warn() {
  doctor_warnings=$((doctor_warnings + 1))
  printf 'WARN  %-28s %s\n' "$1" "$2"
}

skidbladnir_doctor_fail() {
  doctor_failures=$((doctor_failures + 1))
  printf 'FAIL  %-28s %s\n' "$1" "$2"
}

skidbladnir_converge() (
  set -euo pipefail
  umask 077
  local platform="$1"
  local home asset manifest_platform pin_line version source_sha archive_sha
  local staging archive extracted_members
  local config_source hooks_source notify_source
  local config_dir share_dir state_dir tailscale_cli context
  local launcher_source service_source service_target
  local release_transaction_active=0

  require_cmd curl
  require_cmd jq
  require_cmd tar
  home="$(dev_server_home)"
  asset="$(skidbladnir_asset_name "$platform")"
  manifest_platform="$(skidbladnir_manifest_platform "$platform")"
  pin_line="$(skidbladnir_release_values "$platform")" || die "Skidbladnir release pin is pending; root must publish and pin the exact release"
  IFS=$'\t' read -r version source_sha archive_sha <<<"$pin_line"

  staging="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-skidbladnir.XXXXXX")"
  trap skidbladnir_converge_cleanup EXIT
  archive="$staging/$asset"
  curl -fsSL "https://github.com/NielsdaWheelz/skidbladnir/releases/download/$version/$asset" -o "$archive"
  [[ "$(skidbladnir_sha256 "$archive")" == "$archive_sha" ]] || die "Skidbladnir release archive digest differs from the pin"
  extracted_members="$(tar -tzf "$archive" | LC_ALL=C sort)"
  [[ "$extracted_members" == $'characters.json\nrelease.json\nskidbladnir' ]] || die "Skidbladnir release archive has unexpected members"
  tar -xzf "$archive" -C "$staging"
  [[ -f "$staging/skidbladnir" && ! -L "$staging/skidbladnir" && -x "$staging/skidbladnir" ]] ||
    die "Skidbladnir release binary is not an executable regular file"
  [[ -f "$staging/characters.json" && ! -L "$staging/characters.json" ]] ||
    die "Skidbladnir release catalogue is not a regular file"
  [[ -f "$staging/release.json" && ! -L "$staging/release.json" ]] ||
    die "Skidbladnir release manifest is not a regular file"
  [[ "$("$staging/skidbladnir" version)" == "$version $source_sha" ]] || die "Skidbladnir binary version differs from the pin"
  jq -e --arg platform "$manifest_platform" --arg source "$source_sha" --arg version "$version" '
    type == "object" and keys == ["platform", "sourceSha", "version"] and
    .platform == $platform and .sourceSha == $source and .version == $version
  ' "$staging/release.json" >/dev/null || die "Skidbladnir release manifest differs from the pin"
  skidbladnir_require_tmux_runtime "$platform"

  config_dir="$home/.config/skidbladnir"
  share_dir="$home/.local/share/skidbladnir"
  state_dir="$home/.local/state/skidbladnir"
  install -d -m 0700 "$config_dir" "$state_dir"
  install -d -m 0755 "$home/.local/bin" "$share_dir"
  skidbladnir_changed=0
  skidbladnir_recover_release_transaction "$home" "$share_dir"

  launcher_source="$dev_server_root/assets/skidbladnir/skidbladnir-launch"
  skidbladnir_install_owned "$launcher_source" "$home/.local/bin/skidbladnir-launch" 0755
  if [[ "$platform" == macos ]]; then
    service_source="$dev_server_root/assets/skidbladnir/dev.niels.skidbladnir.plist"
    service_target="$home/Library/LaunchAgents/dev.niels.skidbladnir.plist"
  else
    service_source="$dev_server_root/assets/skidbladnir/skidbladnir.service"
    service_target="$home/.config/systemd/user/skidbladnir.service"
  fi
  install -d -m 0755 "$(dirname "$service_target")"
  skidbladnir_install_owned "$service_source" "$service_target" 0644

  if [[ ! -e "$config_dir/machine-handle" && ! -L "$config_dir/machine-handle" ]]; then
    "$staging/skidbladnir" machine init --file="$config_dir/machine-handle" >/dev/null
  fi
  skidbladnir_secret_valid "$config_dir/machine-handle" '^mh-[0-9a-f]{32}$' || die "Skidbladnir machine handle is invalid"
  if [[ ! -e "$config_dir/bearer" && ! -L "$config_dir/bearer" ]]; then
    "$staging/skidbladnir" bearer mint --file="$config_dir/bearer" >/dev/null
  fi
  skidbladnir_secret_valid "$config_dir/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || die "Skidbladnir bearer is invalid"

  skidbladnir_begin_release_transaction "$home" "$share_dir"
  release_transaction_active=1
  skidbladnir_install_owned "$staging/skidbladnir" "$home/.local/bin/skidbladnir" 0755
  skidbladnir_install_owned "$staging/characters.json" "$share_dir/characters.json" 0644
  skidbladnir_install_owned "$staging/release.json" "$share_dir/release.json" 0644
  skidbladnir_install_owned "$archive" "$share_dir/release-bundle.tar.gz" 0644
  skidbladnir_commit_release_transaction "$home" "$share_dir" \
    "$staging/skidbladnir" "$staging/characters.json" "$staging/release.json" "$archive"
  release_transaction_active=0

  config_source="$(skidbladnir_host_config_source "$platform")"
  skidbladnir_install_owned "$config_source" "$config_dir/host-config.json" 0600
  if [[ "$platform" == macos ]]; then
    hooks_source="$dev_server_root/assets/skidbladnir/status-hooks-macbook.json"
    notify_source="$dev_server_root/assets/skidbladnir/skid-notify-macbook"
  else
    hooks_source="$dev_server_root/assets/skidbladnir/status-hooks-linux.json"
    notify_source="$dev_server_root/assets/skidbladnir/skid-notify-linux"
  fi
  skidbladnir_install_owned "$notify_source" "$home/.local/bin/skid-notify" 0755
  for context in personal work work2; do
    install -d -m 0700 "$home/.codex-$context"
    skidbladnir_install_owned "$hooks_source" "$home/.codex-$context/hooks.json" 0600
  done
  skidbladnir_configure_codex_notify "$home"

  if [[ "$platform" == macos ]]; then
    skidbladnir_install_macos_service "$home"
  else
    skidbladnir_install_linux_service "$home"
  fi
  tailscale_cli="$(skidbladnir_tailscale_cli)" || {
    warn "Skidbladnir Serve pending; Tailscale CLI is unavailable"
    exit 0
  }
  skidbladnir_configure_serve "$tailscale_cli"
)

skidbladnir_doctor() {
  local platform="$1"
  local home config_dir share_dir binary config desired_config pin_line version source_sha archive_sha
  local current_version current_binary_sha current_characters_sha current_release_sha
  local expected_binary_sha expected_characters_sha expected_release_sha bundle bundle_members
  local tailscale_cli tmux_path tmux_version serve_status
  local service_source service_target
  home="$(dev_server_home)"
  config_dir="$home/.config/skidbladnir"
  share_dir="$home/.local/share/skidbladnir"
  binary="$home/.local/bin/skidbladnir"
  config="$config_dir/host-config.json"
  desired_config="$(skidbladnir_host_config_source "$platform")"

  pin_line="$(skidbladnir_release_values "$platform" 2>/dev/null || true)"
  if [[ -z "$pin_line" ]]; then
    skidbladnir_doctor_fail skidbladnir.artifact.version "release pin pending; root must pin the published tag and source SHA"
    skidbladnir_doctor_fail skidbladnir.artifact.digest "release pin pending; root must pin both host archive digests"
  else
    IFS=$'\t' read -r version source_sha archive_sha <<<"$pin_line"
    current_version="$($binary version 2>/dev/null || true)"
    if [[ ! -e "$share_dir/.release-transaction" && ! -L "$share_dir/.release-transaction" &&
      -f "$binary" && ! -L "$binary" && -x "$binary" &&
      "$current_version" == "$version $source_sha" &&
      -f "$share_dir/release.json" && ! -L "$share_dir/release.json" ]] &&
      jq -e --arg platform "$(skidbladnir_manifest_platform "$platform")" --arg source "$source_sha" --arg version "$version" '
        type == "object" and keys == ["platform", "sourceSha", "version"] and
        .platform == $platform and .sourceSha == $source and .version == $version
      ' "$share_dir/release.json" >/dev/null 2>&1; then
      skidbladnir_doctor_pass skidbladnir.artifact.version "$version at source $source_sha"
    else
      skidbladnir_doctor_fail skidbladnir.artifact.version "installed artifact differs; run the platform converge command"
    fi
    bundle="$share_dir/release-bundle.tar.gz"
    bundle_members=""
    if [[ -f "$bundle" && ! -L "$bundle" &&
      "$(skidbladnir_file_mode "$bundle" 2>/dev/null || true)" == 644 &&
      "$(skidbladnir_sha256 "$bundle" 2>/dev/null || true)" == "$archive_sha" ]]; then
      bundle_members="$(tar -tzf "$bundle" 2>/dev/null | LC_ALL=C sort || true)"
    fi
    expected_binary_sha=""
    expected_characters_sha=""
    expected_release_sha=""
    if [[ "$bundle_members" == $'characters.json\nrelease.json\nskidbladnir' ]]; then
      expected_binary_sha="$(skidbladnir_archive_member_sha256 "$bundle" skidbladnir 2>/dev/null || true)"
      expected_characters_sha="$(skidbladnir_archive_member_sha256 "$bundle" characters.json 2>/dev/null || true)"
      expected_release_sha="$(skidbladnir_archive_member_sha256 "$bundle" release.json 2>/dev/null || true)"
    fi
    current_binary_sha=""
    if [[ -f "$binary" && ! -L "$binary" && -x "$binary" &&
      "$(skidbladnir_file_mode "$binary" 2>/dev/null || true)" == 755 ]]; then
      current_binary_sha="$(skidbladnir_sha256 "$binary" 2>/dev/null || true)"
    fi
    current_characters_sha=""
    if [[ -f "$share_dir/characters.json" && ! -L "$share_dir/characters.json" &&
      "$(skidbladnir_file_mode "$share_dir/characters.json" 2>/dev/null || true)" == 644 ]]; then
      current_characters_sha="$(skidbladnir_sha256 "$share_dir/characters.json" 2>/dev/null || true)"
    fi
    current_release_sha=""
    if [[ -f "$share_dir/release.json" && ! -L "$share_dir/release.json" &&
      "$(skidbladnir_file_mode "$share_dir/release.json" 2>/dev/null || true)" == 644 ]]; then
      current_release_sha="$(skidbladnir_sha256 "$share_dir/release.json" 2>/dev/null || true)"
    fi
    if [[ ! -e "$share_dir/.release-transaction" && ! -L "$share_dir/.release-transaction" &&
      "$expected_binary_sha" =~ ^[0-9a-f]{64}$ &&
      "$current_binary_sha" == "$expected_binary_sha" &&
      "$expected_characters_sha" =~ ^[0-9a-f]{64}$ &&
      "$current_characters_sha" == "$expected_characters_sha" &&
      "$expected_release_sha" =~ ^[0-9a-f]{64}$ &&
      "$current_release_sha" == "$expected_release_sha" ]]; then
      skidbladnir_doctor_pass skidbladnir.artifact.digest "pinned archive and all installed release members match"
    else
      skidbladnir_doctor_fail skidbladnir.artifact.digest "artifact digest differs; run the platform converge command"
    fi
  fi

  if skidbladnir_owned_config_matches "$platform" "$home"; then
    skidbladnir_doctor_pass skidbladnir.config "strict $platform host config, hooks, and notifier installed"
  else
    skidbladnir_doctor_fail skidbladnir.config "owned host config, hooks, or notifier differs; run the platform converge command"
  fi

  if skidbladnir_secret_valid "$config_dir/machine-handle" '^mh-[0-9a-f]{32}$' &&
    skidbladnir_secret_valid "$config_dir/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'; then
    skidbladnir_doctor_pass skidbladnir.secrets "machine handle and bearer are canonical mode-0600 files"
  else
    skidbladnir_doctor_fail skidbladnir.secrets "credential files are absent, malformed, or not mode 0600"
  fi

  if [[ "$platform" == macos ]]; then
    service_source="$dev_server_root/assets/skidbladnir/dev.niels.skidbladnir.plist"
    service_target="$home/Library/LaunchAgents/dev.niels.skidbladnir.plist"
    if [[ -f "$service_target" && ! -L "$service_target" ]] &&
      cmp -s "$service_source" "$service_target" &&
      [[ "$(skidbladnir_file_mode "$service_target" 2>/dev/null)" == 644 ]] &&
      launchctl print "gui/$(id -u)/dev.niels.skidbladnir" 2>/dev/null |
      grep -Eq '^[[:space:]]*state = running$'; then
      skidbladnir_doctor_pass skidbladnir.service "LaunchAgent definition matches and is running"
    else
      skidbladnir_doctor_fail skidbladnir.service "LaunchAgent definition or runtime differs; run ./workstation converge"
    fi
  else
    service_source="$dev_server_root/assets/skidbladnir/skidbladnir.service"
    service_target="$home/.config/systemd/user/skidbladnir.service"
    if [[ -f "$service_target" && ! -L "$service_target" ]] &&
      cmp -s "$service_source" "$service_target" &&
      [[ "$(skidbladnir_file_mode "$service_target" 2>/dev/null)" == 644 ]] &&
      systemctl --user is-enabled --quiet skidbladnir.service &&
      systemctl --user is-active --quiet skidbladnir.service; then
      skidbladnir_doctor_pass skidbladnir.service "systemd user definition matches and is enabled and active"
    else
      skidbladnir_doctor_fail skidbladnir.service "systemd user definition or runtime differs; run the platform converge command"
    fi
  fi

  if skidbladnir_authenticated_loopback "$config_dir" pressure >/dev/null 2>&1; then
    skidbladnir_doctor_pass skidbladnir.loopback "authenticated tmux-free loopback pressure endpoint is healthy"
  else
    skidbladnir_doctor_fail skidbladnir.loopback "tmux-free loopback pressure endpoint is unhealthy; inspect the gateway service"
  fi

  tailscale_cli="$(skidbladnir_tailscale_cli 2>/dev/null || true)"
  serve_status=""
  [[ -z "$tailscale_cli" ]] || serve_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" serve status --json 2>/dev/null || true)"
  if printf '%s' "$serve_status" | jq -e '
    type == "object" and
    (. as $status |
    [((.Web // {}) | to_entries[]) |
      select(.key | endswith(":8443"))] as $owned |
      ($owned | length > 0) and
      any($owned[]; (($status.AllowFunnel // {})[.key] // false) == true))
  ' >/dev/null 2>&1; then
    skidbladnir_doctor_fail skidbladnir.serve \
      "public Funnel is enabled on HTTPS 8443; run tailscale funnel --https=8443 off, then converge again"
  elif printf '%s' "$serve_status" | jq -e '
    type == "object" and .TCP["8443"].HTTPS == true and
    ([((.Web // {}) | to_entries[]) |
      select(.key | endswith(":8443"))] as $owned |
      ($owned | length == 1) and
      ($owned[0].value.Handlers == {"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}) and
      (((.AllowFunnel // {})[$owned[0].key] // false) == false))
  ' >/dev/null 2>&1; then
    skidbladnir_doctor_pass skidbladnir.serve "private HTTPS 8443 exposes only loopback /v1"
  else
    skidbladnir_doctor_fail skidbladnir.serve "dedicated Serve mapping missing; sign in to Tailscale and converge again"
  fi

  tmux_path="$(jq -er '.tmux.path' "$desired_config" 2>/dev/null || true)"
  tmux_version="$(jq -er '.tmux.version' "$desired_config" 2>/dev/null || true)"
  if [[ -x "$tmux_path" && "$($tmux_path -V 2>/dev/null || true)" == "$tmux_version" ]]; then
    skidbladnir_doctor_pass skidbladnir.tmux "$tmux_version available at the configured path"
  else
    skidbladnir_doctor_fail skidbladnir.tmux "configured tmux path or version differs; run the platform converge command"
  fi

  if [[ -n "$tailscale_cli" ]] && TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null |
    jq -e '.BackendState == "Running"' >/dev/null; then
    skidbladnir_doctor_pass skidbladnir.tailscale "Tailscale is signed in"
  else
    skidbladnir_doctor_fail skidbladnir.tailscale "Tailscale is not signed in; complete the one-time login"
  fi
}

skidbladnir_reconciled_lifetime_digest_local() (
  set -euo pipefail
  local home config_dir
  home="$(dev_server_home)"
  config_dir="$home/.config/skidbladnir"
  skidbladnir_authenticated_loopback "$config_dir" sessions 2>/dev/null |
    jq -ceS '
      if (
        type == "object" and
        (.machine | type == "object" and (.handle | type == "string" and test("^mh-[0-9a-f]{32}$"))) and
        (.sessions | type == "array") and
        all(.sessions[];
          type == "object" and
          (.id | type == "string" and test("^\\$[1-9][0-9]*$")) and
          (.tmuxName | type == "string" and length > 0) and
          (.identityToken | type == "string" and test("^v1-[0-9a-f]{32}\\.[1-9][0-9]*\\.[1-9][0-9]*\\.[0-9]+$"))) and
        ([.sessions[].identityToken] | unique | length) == (.sessions | length)
      ) then
        {
          machineHandle: .machine.handle,
          sessions: (.sessions | map({id, tmuxName, identityToken}) | sort_by(.id, .tmuxName, .identityToken))
        }
      else error("invalid lifetime inventory") end
    ' 2>/dev/null | skidbladnir_sha256_stream
)

skidbladnir_credentials_digest_local() (
  set -euo pipefail
  local home config_dir
  home="$(dev_server_home)"
  config_dir="$home/.config/skidbladnir"
  skidbladnir_secret_valid "$config_dir/machine-handle" '^mh-[0-9a-f]{32}$'
  skidbladnir_secret_valid "$config_dir/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$'
  {
    printf 'skidbladnir-machine-handle\0'
    cat "$config_dir/machine-handle"
    printf '\0skidbladnir-bearer\0'
    cat "$config_dir/bearer"
  } | skidbladnir_sha256_stream
)

skidbladnir_acceptance_service_intent() {
  local platform="$1"
  local home service_source service_target
  home="$(dev_server_home)"
  case "$platform" in
  macos)
    service_source="$dev_server_root/assets/skidbladnir/dev.niels.skidbladnir.plist"
    service_target="$home/Library/LaunchAgents/dev.niels.skidbladnir.plist"
    [[ -f "$service_target" && ! -L "$service_target" ]] &&
      cmp -s "$service_source" "$service_target" &&
      [[ "$(skidbladnir_file_mode "$service_target" 2>/dev/null)" == 644 ]] &&
      launchctl print "gui/$(id -u)/dev.niels.skidbladnir" 2>/dev/null |
      grep -Eq '^[[:space:]]*state = running$'
    ;;
  devbox | arch)
    service_source="$dev_server_root/assets/skidbladnir/skidbladnir.service"
    service_target="$home/.config/systemd/user/skidbladnir.service"
    [[ -f "$service_target" && ! -L "$service_target" ]] &&
      cmp -s "$service_source" "$service_target" &&
      [[ "$(skidbladnir_file_mode "$service_target" 2>/dev/null)" == 644 ]] &&
      systemctl --user is-enabled --quiet skidbladnir.service &&
      systemctl --user is-active --quiet skidbladnir.service &&
      [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" == yes ]]
    ;;
  *) die "unsupported Skidbladnir acceptance platform: $platform" ;;
  esac
}

skidbladnir_boot_identity_digest_local() (
  set -euo pipefail
  local boot_identity platform
  platform="$(uname -s)"
  case "$platform" in
  Darwin)
    boot_identity="$(/usr/sbin/sysctl -n kern.boottime)"
    ;;
  Linux)
    [[ -r /proc/sys/kernel/random/boot_id ]] ||
      die "Linux boot identity is unavailable"
    boot_identity="$(tr -d '\n' </proc/sys/kernel/random/boot_id)"
    [[ "$boot_identity" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] ||
      die "Linux boot identity is invalid"
    ;;
  *) die "unsupported reboot acceptance platform: $platform" ;;
  esac
  [[ -n "$boot_identity" && "${#boot_identity}" -le 256 ]] ||
    die "boot identity is invalid"
  {
    printf 'skidbladnir-boot-identity-v1\0%s\0' "$platform"
    printf '%s' "$boot_identity"
  } | skidbladnir_sha256_stream
)

skidbladnir_reboot_acceptance_file() {
  printf '%s/.local/state/skidbladnir/reboot-acceptance.json\n' "$(dev_server_home)"
}

skidbladnir_reboot_acceptance_require_capability() {
  local label="$1"
  if [[ "${SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE:-}" != reboot-acceptance-v1 ]]; then
    printf 'NOT_RUN  skidbladnir.accept-host.reboot %s exact reboot acceptance capability is required; no checkpoint was changed\n' "$label" >&2
    return 64
  fi
}

skidbladnir_reboot_acceptance_validate_host() {
  case "$1:$2" in
  macos:Local | devbox:DevServer | arch:Arch) ;;
  *) die "unsupported Skidbladnir reboot acceptance host: $2" ;;
  esac
}

skidbladnir_reboot_acceptance_require_health() {
  local platform="$1"
  local label="$2"
  doctor_reset
  skidbladnir_doctor "$platform"
  if ((doctor_failures != 0 || doctor_warnings != 0)); then
    doctor_summary "$label Skidbladnir reboot acceptance" || true
    die "Skidbladnir doctor is not completely healthy for reboot acceptance on $label"
  fi
  doctor_summary "$label Skidbladnir reboot acceptance"
  skidbladnir_acceptance_service_intent "$platform" ||
    die "Skidbladnir service boot/login intent failed on $label"
}

skidbladnir_prepare_reboot_local() (
  set -euo pipefail
  set +x
  local platform="$1"
  local label="$2"
  local evidence state_dir temporary=""
  local boot_digest credentials_digest release_pin_digest
  skidbladnir_reboot_acceptance_require_capability "$label" || return
  skidbladnir_reboot_acceptance_validate_host "$platform" "$label"
  skidbladnir_release_values "$platform" >/dev/null ||
    die "Skidbladnir release pin is pending or invalid on $label"
  skidbladnir_reboot_acceptance_require_health "$platform" "$label"

  boot_digest="$(skidbladnir_boot_identity_digest_local)"
  credentials_digest="$(skidbladnir_credentials_digest_local)"
  release_pin_digest="$(skidbladnir_sha256 "$skidbladnir_release_pin_file")"
  [[ "$boot_digest" =~ ^[0-9a-f]{64}$ &&
    "$credentials_digest" =~ ^[0-9a-f]{64}$ &&
    "$release_pin_digest" =~ ^[0-9a-f]{64}$ ]] ||
    die "Skidbladnir reboot checkpoint inputs are invalid on $label"

  evidence="$(skidbladnir_reboot_acceptance_file)"
  state_dir="$(dirname "$evidence")"
  if [[ -e "$state_dir" || -L "$state_dir" ]]; then
    [[ -d "$state_dir" && ! -L "$state_dir" && -O "$state_dir" &&
      "$(skidbladnir_file_mode "$state_dir" 2>/dev/null || true)" == 700 ]] ||
      die "Skidbladnir state directory is not a user-owned mode-0700 directory"
  else
    install -d -m 0700 "$state_dir"
  fi
  [[ ! -e "$evidence" && ! -L "$evidence" ]] ||
    die "A reboot acceptance checkpoint already exists on $label; verify it before preparing another reboot"
  temporary="$(mktemp "$state_dir/.reboot-acceptance.XXXXXX")"
  trap '[[ -z "$temporary" ]] || /bin/unlink "$temporary" 2>/dev/null || true' EXIT
  jq -nS --arg platform "$platform" --arg label "$label" \
    --arg boot "$boot_digest" --arg credentials "$credentials_digest" \
    --arg release_pin "$release_pin_digest" '
      {
        schemaVersion: 1,
        platform: $platform,
        label: $label,
        bootDigest: $boot,
        credentialsDigest: $credentials,
        releasePinDigest: $release_pin
      }
    ' >"$temporary"
  chmod 0600 "$temporary"
  mv "$temporary" "$evidence"
  temporary=""
  trap - EXIT
  printf 'PASS  skidbladnir.accept-host.reboot.prepare %s reboot checkpoint is ready\n' "$label"
)

skidbladnir_verify_reboot_local() (
  set -euo pipefail
  set +x
  local platform="$1"
  local label="$2"
  local evidence evidence_bytes observed_keys values
  local prior_boot prior_credentials prior_release_pin
  local current_boot current_credentials current_release_pin
  skidbladnir_reboot_acceptance_require_capability "$label" || return
  skidbladnir_reboot_acceptance_validate_host "$platform" "$label"
  evidence="$(skidbladnir_reboot_acceptance_file)"
  [[ -f "$evidence" && ! -L "$evidence" && -O "$evidence" &&
    "$(skidbladnir_file_mode "$evidence" 2>/dev/null || true)" == 600 ]] ||
    die "Skidbladnir reboot checkpoint is not a user-owned mode-0600 regular file on $label"
  evidence_bytes="$(LC_ALL=C wc -c <"$evidence" | tr -d '[:space:]')"
  [[ "$evidence_bytes" =~ ^[1-9][0-9]{0,3}$ && "$evidence_bytes" -le 2048 ]] ||
    die "Skidbladnir reboot checkpoint size is invalid on $label"
  observed_keys="$(
    jq --stream -er 'select(length == 2 and (.[0] | length) == 1) | .[0][0]' "$evidence" |
      LC_ALL=C sort
  )" || die "Skidbladnir reboot checkpoint JSON is invalid on $label"
  [[ "$observed_keys" == $'bootDigest\ncredentialsDigest\nlabel\nplatform\nreleasePinDigest\nschemaVersion' ]] ||
    die "Skidbladnir reboot checkpoint members are invalid on $label"
  values="$(jq -er --arg platform "$platform" --arg label "$label" '
    if type == "object" and
      keys == ["bootDigest","credentialsDigest","label","platform","releasePinDigest","schemaVersion"] and
      .schemaVersion == 1 and .platform == $platform and .label == $label and
      (.bootDigest | type == "string" and test("^[0-9a-f]{64}$")) and
      (.credentialsDigest | type == "string" and test("^[0-9a-f]{64}$")) and
      (.releasePinDigest | type == "string" and test("^[0-9a-f]{64}$"))
    then [.bootDigest, .credentialsDigest, .releasePinDigest] | @tsv
    else error("invalid reboot checkpoint") end
  ' "$evidence")" || die "Skidbladnir reboot checkpoint schema is invalid on $label"
  IFS=$'\t' read -r prior_boot prior_credentials prior_release_pin <<<"$values"

  current_boot="$(skidbladnir_boot_identity_digest_local)"
  if [[ "$current_boot" == "$prior_boot" ]]; then
    printf 'NOT_RUN  skidbladnir.accept-host.reboot %s boot identity has not changed; reboot before verification\n' "$label" >&2
    return 65
  fi
  skidbladnir_release_values "$platform" >/dev/null ||
    die "Skidbladnir release pin is pending or invalid on $label"
  current_release_pin="$(skidbladnir_sha256 "$skidbladnir_release_pin_file")"
  [[ "$current_release_pin" == "$prior_release_pin" ]] ||
    die "Skidbladnir release pin changed across reboot on $label"
  skidbladnir_reboot_acceptance_require_health "$platform" "$label"
  current_credentials="$(skidbladnir_credentials_digest_local)"
  [[ "$current_credentials" == "$prior_credentials" ]] ||
    die "Skidbladnir credentials changed across reboot on $label"
  /bin/unlink "$evidence"
  printf 'PASS  skidbladnir.accept-host.reboot %s reboot/login persistence preserved release and credentials\n' "$label"
)

skidbladnir_accept_host_local() (
  set -euo pipefail
  set +x
  local platform="$1"
  local label="$2"
  local credentials_before credentials_after lifetime_before lifetime_after
  if [[ "${SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE:-}" != host-acceptance-v1 ]]; then
    printf 'NOT_RUN  skidbladnir.accept-host        exact host acceptance capability is required; no host was touched\n' >&2
    return 64
  fi
  case "$platform:$label" in
  macos:Local | devbox:DevServer | arch:Arch) ;;
  *) die "unsupported Skidbladnir acceptance host: $label" ;;
  esac

  credentials_before="$(skidbladnir_credentials_digest_local)"
  lifetime_before="$(skidbladnir_reconciled_lifetime_digest_local)"
  [[ "$credentials_before" =~ ^[0-9a-f]{64}$ && "$lifetime_before" =~ ^[0-9a-f]{64}$ ]] ||
    die "Skidbladnir acceptance precondition failed on $label"
  skidbladnir_converge "$platform" >/dev/null
  skidbladnir_converge "$platform" >/dev/null
  doctor_reset
  skidbladnir_doctor "$platform"
  if ((doctor_failures != 0 || doctor_warnings != 0)); then
    doctor_summary "$label Skidbladnir acceptance" || true
    die "Skidbladnir doctor is not completely healthy after convergence on $label"
  fi
  doctor_summary "$label Skidbladnir acceptance"
  credentials_after="$(skidbladnir_credentials_digest_local)"
  lifetime_after="$(skidbladnir_reconciled_lifetime_digest_local)"
  [[ "$credentials_after" == "$credentials_before" ]] ||
    die "Skidbladnir credentials changed during acceptance on $label"
  [[ "$lifetime_after" == "$lifetime_before" ]] ||
    die "Skidbladnir reconciled tmux lifetime changed during acceptance on $label"
  skidbladnir_acceptance_service_intent "$platform" ||
    die "Skidbladnir service boot/login intent failed on $label"

  printf 'PASS  skidbladnir.accept-host        %s identity-preserving reinstall converged twice; reconciled lifetime and service boot/login intent hold\n' "$label"
  printf 'NOT_RUN  skidbladnir.accept-host.reboot %s run prepare-reboot before the approved reboot, then verify-reboot after login\n' "$label"
)
