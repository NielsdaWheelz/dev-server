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

skidbladnir_status_hooks_source() {
  case "$1" in
  devbox) printf '%s/assets/skidbladnir/status-hooks-devbox.json\n' "$dev_server_root" ;;
  arch) printf '%s/assets/skidbladnir/status-hooks-arch.json\n' "$dev_server_root" ;;
  macos) printf '%s/assets/skidbladnir/status-hooks-macbook.json\n' "$dev_server_root" ;;
  *) die "unsupported Skidbladnir platform: $1" ;;
  esac
}

skidbladnir_remote_target() {
  case "$1" in
  DevServer) printf 'dev-server\n' ;;
  Arch) printf 'nnandal@arch\n' ;;
  *) die "unsupported Skidbladnir remote target: $1" ;;
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
  dev_server_sha256 "$1"
}

skidbladnir_sha256_stream() {
  dev_server_sha256_stream
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

skidbladnir_owned_file_specs() {
  printf '%s\n' \
    'launcher 0755' \
    'service 0644' \
    'binary 0755' \
    'catalogue 0644' \
    'manifest 0644' \
    'bundle 0644' \
    'host-config 0600' \
    'notifier 0755' \
    'personal-hooks 0600' \
    'work-hooks 0600' \
    'work2-hooks 0600'
}

skidbladnir_owned_file_target() {
  local platform="$1"
  local home="$2"
  local name="$3"
  case "$platform" in
  devbox | arch | macos) ;;
  *) die "unsupported Skidbladnir platform: $platform" ;;
  esac
  case "$name" in
  launcher) printf '%s/.local/bin/skidbladnir-launch\n' "$home" ;;
  service)
    if [[ "$platform" == macos ]]; then
      printf '%s/Library/LaunchAgents/dev.niels.skidbladnir.plist\n' "$home"
    else
      printf '%s/.config/systemd/user/skidbladnir.service\n' "$home"
    fi
    ;;
  binary) printf '%s/.local/bin/skidbladnir\n' "$home" ;;
  catalogue) printf '%s/.local/share/skidbladnir/characters.json\n' "$home" ;;
  manifest) printf '%s/.local/share/skidbladnir/release.json\n' "$home" ;;
  bundle) printf '%s/.local/share/skidbladnir/release-bundle.tar.gz\n' "$home" ;;
  host-config) printf '%s/.config/skidbladnir/host-config.json\n' "$home" ;;
  notifier) printf '%s/.local/bin/skid-notify\n' "$home" ;;
  personal-hooks) printf '%s/.codex-personal/hooks.json\n' "$home" ;;
  work-hooks) printf '%s/.codex-work/hooks.json\n' "$home" ;;
  work2-hooks) printf '%s/.codex-work2/hooks.json\n' "$home" ;;
  *) die "unsupported Skidbladnir owned file: $name" ;;
  esac
}

skidbladnir_owned_file_source() {
  local platform="$1"
  local staging="$2"
  local archive="$3"
  local name="$4"
  case "$platform" in
  devbox | arch | macos) ;;
  *) die "unsupported Skidbladnir platform: $platform" ;;
  esac
  case "$name" in
  launcher) printf '%s/assets/skidbladnir/skidbladnir-launch\n' "$dev_server_root" ;;
  service)
    if [[ "$platform" == macos ]]; then
      printf '%s/assets/skidbladnir/dev.niels.skidbladnir.plist\n' "$dev_server_root"
    else
      printf '%s/assets/skidbladnir/skidbladnir.service\n' "$dev_server_root"
    fi
    ;;
  binary) printf '%s/skidbladnir\n' "$staging" ;;
  catalogue) printf '%s/characters.json\n' "$staging" ;;
  manifest) printf '%s/release.json\n' "$staging" ;;
  bundle) printf '%s\n' "$archive" ;;
  host-config) skidbladnir_host_config_source "$platform" ;;
  notifier)
    if [[ "$platform" == macos ]]; then
      printf '%s/assets/skidbladnir/skid-notify-macbook\n' "$dev_server_root"
    else
      printf '%s/assets/skidbladnir/skid-notify-linux\n' "$dev_server_root"
    fi
    ;;
  personal-hooks | work-hooks | work2-hooks) skidbladnir_status_hooks_source "$platform" ;;
  *) die "unsupported Skidbladnir owned file: $name" ;;
  esac
}

skidbladnir_preflight_owned_files() {
  local platform="$1"
  local home="$2"
  local staging="$3"
  local archive="$4"
  local name mode source target
  while read -r name mode; do
    source="$(skidbladnir_owned_file_source "$platform" "$staging" "$archive" "$name")"
    [[ -f "$source" && ! -L "$source" ]] ||
      die "Skidbladnir owned source is not a regular file: $source"
    target="$(skidbladnir_owned_file_target "$platform" "$home" "$name")"
    if [[ -e "$target" || -L "$target" ]]; then
      [[ -f "$target" && ! -L "$target" ]] ||
        die "Skidbladnir owned target is not a regular file: $target"
    fi
    [[ -n "$mode" ]] || die "Skidbladnir owned file mode is missing: $name"
  done < <(skidbladnir_owned_file_specs)
}

skidbladnir_release_transaction_remove() {
  local home="$1"
  local share_dir="$home/.local/share/skidbladnir"
  local transaction="$share_dir/.release-transaction"
  [[ -d "$transaction" && ! -L "$transaction" ]] ||
    die "Skidbladnir release transaction is not a private directory"
  rm -R -- "$transaction"
}

skidbladnir_release_activation_marker() {
  local platform="$1"
  local home="$2"
  case "$platform" in
  devbox | arch | macos) ;;
  *) die "unsupported Skidbladnir platform: $platform" ;;
  esac
  printf '%s/.local/share/skidbladnir/.release-activation-required\n' "$home"
}

skidbladnir_release_activation_required() {
  local platform="$1"
  local home="$2"
  local marker marker_platform marker_version marker_source marker_extra value framed
  marker="$(skidbladnir_release_activation_marker "$platform" "$home")"
  if [[ ! -e "$marker" && ! -L "$marker" ]]; then
    return 1
  fi
  [[ -f "$marker" && ! -L "$marker" &&
    "$(skidbladnir_file_mode "$marker" 2>/dev/null)" == 600 ]] ||
    die "Skidbladnir release activation marker is invalid"
  IFS=$'\t' read -r marker_platform marker_version marker_source marker_extra <"$marker" || true
  value="$(cat "$marker")" || die "Skidbladnir release activation marker is unreadable"
  framed="$(
    cat "$marker"
    printf .
  )" || die "Skidbladnir release activation marker is unreadable"
  [[ -z "$marker_extra" && "$marker_platform" == "$platform" &&
    "$marker_version" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ &&
    "$marker_source" =~ ^[0-9a-f]{40}$ &&
    "$value" == "$marker_platform"$'\t'"$marker_version"$'\t'"$marker_source" &&
    "$framed" == "$value"$'\n.' ]] ||
    die "Skidbladnir release activation marker is invalid"
}

skidbladnir_mark_release_activation_required() {
  local platform="$1"
  local home="$2"
  local version="$3"
  local source_sha="$4"
  local marker temporary
  marker="$(skidbladnir_release_activation_marker "$platform" "$home")"
  if [[ -e "$marker" || -L "$marker" ]]; then
    skidbladnir_release_activation_required "$platform" "$home"
  fi
  temporary="$(mktemp "$(dirname "$marker")/.release-activation-required.XXXXXX")"
  if ! printf '%s\t%s\t%s\n' "$platform" "$version" "$source_sha" >"$temporary" ||
    ! chmod 0600 "$temporary" ||
    ! mv -f -- "$temporary" "$marker"; then
    [[ ! -e "$temporary" && ! -L "$temporary" ]] || /bin/unlink "$temporary" 2>/dev/null || true
    die "Could not persist Skidbladnir release activation state"
  fi
  skidbladnir_release_activation_required "$platform" "$home"
}

skidbladnir_resume_release_activation() {
  local platform="$1"
  local home="$2"
  if skidbladnir_release_activation_required "$platform" "$home"; then
    skidbladnir_changed=1
  fi
}

skidbladnir_clear_release_activation() {
  local platform="$1"
  local home="$2"
  local marker
  marker="$(skidbladnir_release_activation_marker "$platform" "$home")"
  if [[ ! -e "$marker" && ! -L "$marker" ]]; then
    return
  fi
  skidbladnir_release_activation_required "$platform" "$home"
  /bin/unlink "$marker" || die "Could not clear Skidbladnir release activation state"
  [[ ! -e "$marker" && ! -L "$marker" ]] ||
    die "Skidbladnir release activation state remains after service activation"
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
  local platform="$1"
  local home="$2"
  local share_dir="$home/.local/share/skidbladnir"
  local transaction="$share_dir/.release-transaction"
  local state temporary_state name mode target
  if [[ ! -e "$transaction" && ! -L "$transaction" ]]; then
    return
  fi
  [[ -d "$transaction" && ! -L "$transaction" &&
    "$(skidbladnir_file_mode "$transaction" 2>/dev/null)" == 700 ]] ||
    die "Skidbladnir release transaction boundary is invalid"
  state="$(cat "$transaction/state" 2>/dev/null || true)"
  if [[ "$state" == preparing ]]; then
    skidbladnir_release_transaction_remove "$home"
    return
  fi
  [[ "$state" == prepared || "$state" == recovering ]] ||
    die "Skidbladnir release transaction state is invalid"
  [[ -f "$transaction/platform" && ! -L "$transaction/platform" &&
    "$(cat "$transaction/platform")" == "$platform" ]] ||
    die "Skidbladnir release transaction platform is invalid"
  temporary_state="$transaction/.state.recovering"
  printf 'recovering\n' >"$temporary_state"
  mv -f -- "$temporary_state" "$transaction/state"
  while read -r name mode; do
    target="$(skidbladnir_owned_file_target "$platform" "$home" "$name")"
    skidbladnir_release_transaction_restore "$target" "$transaction/$name" "$mode"
  done < <(skidbladnir_owned_file_specs)
  skidbladnir_release_transaction_remove "$home"
}

skidbladnir_begin_release_transaction() {
  local platform="$1"
  local home="$2"
  local share_dir="$home/.local/share/skidbladnir"
  local transaction="$share_dir/.release-transaction"
  local prepared_state name mode target
  [[ ! -e "$transaction" && ! -L "$transaction" ]] ||
    die "Skidbladnir release transaction already exists"
  install -d -m 0700 "$transaction"
  printf 'preparing\n' >"$transaction/state"
  printf '%s\n' "$platform" >"$transaction/platform"
  while read -r name mode; do
    target="$(skidbladnir_owned_file_target "$platform" "$home" "$name")"
    skidbladnir_release_transaction_snapshot "$target" "$transaction/$name" "$mode"
  done < <(skidbladnir_owned_file_specs)
  prepared_state="$transaction/.state.prepared"
  printf 'prepared\n' >"$prepared_state"
  mv -f -- "$prepared_state" "$transaction/state"
}

skidbladnir_commit_release_transaction() {
  local platform="$1"
  local home="$2"
  local staging="$3"
  local archive="$4"
  local share_dir="$home/.local/share/skidbladnir"
  local transaction="$share_dir/.release-transaction"
  local name mode source target
  [[ "$(cat "$transaction/state" 2>/dev/null || true)" == prepared &&
  -f "$transaction/platform" && ! -L "$transaction/platform" &&
  "$(cat "$transaction/platform")" == "$platform" ]] ||
    die "Skidbladnir release transaction is not prepared"
  while read -r name mode; do
    source="$(skidbladnir_owned_file_source "$platform" "$staging" "$archive" "$name")"
    target="$(skidbladnir_owned_file_target "$platform" "$home" "$name")"
    [[ -f "$target" && ! -L "$target" ]] &&
      cmp -s "$source" "$target" &&
      [[ "$(skidbladnir_file_mode "$target" 2>/dev/null)" == "${mode#0}" ]] ||
      die "Skidbladnir promoted owned file failed verification: $target"
  done < <(skidbladnir_owned_file_specs)
  skidbladnir_release_transaction_remove "$home"
}

# shellcheck disable=SC2329 # Invoked indirectly by the converge EXIT trap.
skidbladnir_converge_cleanup() {
  local converge_exit=$?
  trap - EXIT
  if [[ "${release_transaction_active:-0}" == 1 ]]; then
    if ! skidbladnir_recover_release_transaction "$platform" "$home"; then
      printf 'Could not restore the prior Skidbladnir owned file set\n' >&2
      converge_exit=1
    fi
  fi
  if [[ -n "${staging:-}" ]]; then
    rm -R -- "$staging" || converge_exit=1
  fi
  exit "$converge_exit"
}

skidbladnir_preflight_codex_notify() {
  local home="$1"
  local notify="$home/.local/bin/skid-notify"
  local desired="notify = [\"$notify\"]"
  local context config
  for context in personal work work2; do
    config="$home/.codex-$context/config.toml"
    if [[ -e "$config" || -L "$config" ]]; then
      [[ -f "$config" && ! -L "$config" ]] ||
        die "Codex config is not a regular file: $config"
      if grep -Eq '^[[:space:]]*notify[[:space:]]*=' "$config"; then
        [[ "$(grep -Fxc "$desired" "$config" || true)" == 1 &&
        "$(grep -Ec '^[[:space:]]*notify[[:space:]]*=' "$config" || true)" == 1 ]] ||
          die "Codex notify configuration conflicts: $config"
      fi
    fi
  done
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
  hooks_source="$(skidbladnir_status_hooks_source "$platform")"
  if [[ "$platform" == macos ]]; then
    notify_source="$dev_server_root/assets/skidbladnir/skid-notify-macbook"
  else
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

skidbladnir_serve_config_is_wholly_owned() {
  jq -e '
    type == "object" and
    ((keys - ["AllowFunnel", "Foreground", "Services", "TCP", "Web"]) | length == 0) and
    .TCP == {"8443":{"HTTPS":true}} and
    (.Web | type == "object" and length > 0 and
      all(to_entries[];
        (.key | endswith(":8443")) and
        (.value | type == "object" and keys == ["Handlers"]) and
        (.value.Handlers | type == "object" and length > 0 and
          all(to_entries[];
            ((.key == "/") and (.value == {"Proxy":"http://127.0.0.1:7341"})) or
            ((.key == "/v1") and (.value == {"Proxy":"http://127.0.0.1:7341/v1"})))))) and
    (((has("AllowFunnel") | not) or .AllowFunnel == {})) and
    (((has("Foreground") | not) or .Foreground == {})) and
    (((has("Services") | not) or .Services == {}))
  ' >/dev/null
}

skidbladnir_serve_config_is_desired_for_host() {
  local hostname="$1"
  jq -e --arg key "$hostname:8443" '
    type == "object" and
    ((keys - ["AllowFunnel", "Foreground", "Services", "TCP", "Web"]) | length == 0) and
    .TCP == {"8443":{"HTTPS":true}} and
    .Web == {($key):{"Handlers":{"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}}} and
    (((has("AllowFunnel") | not) or .AllowFunnel == {})) and
    (((has("Foreground") | not) or .Foreground == {})) and
    (((has("Services") | not) or .Services == {}))
  ' >/dev/null
}

skidbladnir_canonical_single_json() {
  jq -cSse '
    if length == 1 then .[0]
    else error("expected exactly one JSON document")
    end
  '
}

skidbladnir_tailscale_current_dns_name() {
  local dns_name
  dns_name="$(jq -er '
    if type == "object" and
      .BackendState == "Running" and
      (.Self.DNSName | type == "string")
    then .Self.DNSName
    else error("running Tailscale DNS name unavailable")
    end
  ')" || return 1
  [[ "${#dns_name}" -ge 4 && "${#dns_name}" -le 254 &&
    "$dns_name" =~ ^[a-z0-9][a-z0-9.-]*[a-z0-9][.]$ &&
    "$dns_name" != *..* && "$dns_name" != *.-* && "$dns_name" != *-.* ]] || return 1
  printf '%s\n' "${dns_name%.}"
}

skidbladnir_runtime_os() {
  uname -s
}

skidbladnir_localapi_get_etag() {
  LC_ALL=C awk '
    { sub(/\r$/, "") }
    $1 ~ /^HTTP\/[0-9]+([.][0-9]+)?$/ {
      status = $2
      status_count++
      next
    }
    tolower($0) ~ /^etag:[[:space:]]*/ {
      etag = $0
      sub(/^[^:]*:[[:space:]]*/, "", etag)
      etag_count++
      next
    }
    tolower($0) ~ /^content-type:[[:space:]]*/ {
      content_type = $0
      sub(/^[^:]*:[[:space:]]*/, "", content_type)
      content_type_count++
    }
    END {
      if (status_count != 1 || status != "200" ||
          etag_count != 1 ||
          content_type_count != 1 || tolower(content_type) != "application/json") exit 1
      print etag
    }
  ' "$1"
}

skidbladnir_localapi_response_is_200() {
  LC_ALL=C awk '
    { sub(/\r$/, "") }
    $1 ~ /^HTTP\/[0-9]+([.][0-9]+)?$/ {
      status = $2
      status_count++
    }
    END { exit !(status_count == 1 && status == "200") }
  ' "$1"
}

skidbladnir_reconcile_owned_serve_hostnames() (
  set -euo pipefail
  set +x
  local tailscale_cli="$1"
  local platform="$2"
  local hostname="$3"
  local expected_status="$4"
  local runtime_os credentials transport socket token port rest
  local workspace headers post_headers observed desired header_bytes post_header_bytes body_bytes etag
  local expected_canonical observed_canonical pre_status pre_hostname
  local localapi_url
  umask 077
  runtime_os="$(skidbladnir_runtime_os)" ||
    die "Could not identify the runtime for stale Serve hostname repair"
  credentials="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" debug local-creds 2>/dev/null)" ||
    die "Tailscale LocalAPI credentials are unavailable for stale Serve hostname repair"
  [[ "$credentials" != *$'\n'* ]] ||
    die "Tailscale LocalAPI credentials have an unsupported shape"
  case "$platform:$runtime_os" in
  arch:Linux | devbox:Linux)
    local prefix='curl --unix-socket '
    local suffix=' http://local-tailscaled.sock/localapi/v0/status'
    [[ "$credentials" == "$prefix"*"$suffix" ]] ||
      die "Linux stale Serve hostname repair requires Tailscale's Unix-socket LocalAPI"
    socket="${credentials#"$prefix"}"
    socket="${socket%"$suffix"}"
    [[ "${#socket}" -le 4096 && "$socket" =~ ^/[A-Za-z0-9._/-]+$ &&
      "$socket" != *//* && "$socket" != */../* && "$socket" != */./* &&
      -S "$socket" && ! -L "$socket" ]] ||
      die "Tailscale's Unix-socket LocalAPI path is invalid"
    transport=unix
    token=''
    localapi_url='http://local-tailscaled.sock/localapi/v0/serve-config'
    ;;
  macos:Darwin)
    local prefix='curl -u:'
    local marker=' http://localhost:'
    local suffix='/localapi/v0/status'
    [[ "$credentials" == "$prefix"*"$marker"*"$suffix" ]] ||
      die "macOS stale Serve hostname repair requires Tailscale's loopback token LocalAPI"
    rest="${credentials#"$prefix"}"
    token="${rest%%"$marker"*}"
    rest="${rest#*"$marker"}"
    port="${rest%"$suffix"}"
    [[ "${#token}" -ge 16 && "${#token}" -le 128 && "$token" =~ ^[A-Za-z0-9_-]+$ &&
      "$port" =~ ^[1-9][0-9]{0,4}$ && "$port" -le 65535 ]] ||
      die "Tailscale's loopback token LocalAPI credentials are invalid"
    transport=tcp-token
    socket=''
    localapi_url="http://127.0.0.1:$port/localapi/v0/serve-config"
    ;;
  *)
    die "Automatic stale Serve hostname repair is unsupported on this platform and runtime"
    ;;
  esac

  localapi_curl() {
    local curl_status
    if [[ "$transport" == unix ]]; then
      curl -q --noproxy '*' --unix-socket "$socket" "$@"
      curl_status=$?
    else
      printf 'user = ":%s"\n' "$token" |
        curl -q --noproxy '*' --config - "$@"
      curl_status=$?
    fi
    return "$curl_status"
  }

  workspace="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-skidbladnir-serve.XXXXXX")" ||
    die "Could not create the stale Serve hostname repair workspace"
  trap 'rm -rf -- "$workspace"' EXIT
  headers="$workspace/headers"
  post_headers="$workspace/post-headers"
  observed="$workspace/observed.json"
  desired="$workspace/desired.json"

  localapi_curl --silent --show-error --fail \
    --connect-timeout 2 --max-time 5 --max-filesize 65536 \
    --dump-header "$headers" --output "$observed" "$localapi_url" ||
    die "Could not read Tailscale LocalAPI Serve state for atomic stale-hostname repair"
  [[ -f "$headers" && ! -L "$headers" && -f "$observed" && ! -L "$observed" ]] ||
    die "Tailscale LocalAPI Serve response files are invalid"
  header_bytes="$(LC_ALL=C wc -c <"$headers" | tr -d '[:space:]')"
  body_bytes="$(LC_ALL=C wc -c <"$observed" | tr -d '[:space:]')"
  [[ "$header_bytes" =~ ^[1-9][0-9]{0,4}$ && "$header_bytes" -le 16384 ]] ||
    die "Tailscale LocalAPI Serve response headers are invalid"
  [[ "$body_bytes" =~ ^[1-9][0-9]{0,5}$ && "$body_bytes" -le 65536 ]] ||
    die "Tailscale LocalAPI Serve response body is invalid"
  etag="$(skidbladnir_localapi_get_etag "$headers")" ||
    die "Tailscale LocalAPI Serve response status, content type, or ETag is invalid"
  [[ "$etag" =~ ^[0-9a-f]{64}$ ]] ||
    die "Tailscale LocalAPI Serve ETag is invalid"

  expected_canonical="$(printf '%s' "$expected_status" | skidbladnir_canonical_single_json)" ||
    die "The approved CLI Serve snapshot is invalid"
  observed_canonical="$(skidbladnir_canonical_single_json <"$observed")" ||
    die "Tailscale LocalAPI returned other than one Serve JSON document"
  [[ "$observed_canonical" == "$expected_canonical" ]] ||
    die "Tailscale Serve state changed before atomic stale-hostname repair"
  printf '%s' "$observed_canonical" | skidbladnir_serve_config_is_wholly_owned ||
    die "Tailscale Serve state includes unowned data before stale-hostname repair"
  jq -cnS --arg key "$hostname:8443" '
    {
      TCP:{"8443":{HTTPS:true}},
      Web:{($key):{Handlers:{"/v1":{Proxy:"http://127.0.0.1:7341/v1"}}}}
    }
  ' >"$desired" || die "Could not construct the canonical Skidbladnir Serve configuration"

  pre_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null)" ||
    die "Tailscale status is unavailable before atomic stale-hostname repair"
  pre_status="$(printf '%s' "$pre_status" | skidbladnir_canonical_single_json)" ||
    die "Tailscale status is invalid before atomic stale-hostname repair"
  pre_hostname="$(printf '%s' "$pre_status" | skidbladnir_tailscale_current_dns_name)" ||
    die "Tailscale's current DNS hostname is invalid before atomic stale-hostname repair"
  [[ "$pre_hostname" == "$hostname" ]] ||
    die "Tailscale's DNS hostname changed before atomic stale-hostname repair"

  localapi_curl --silent --show-error --fail \
    --connect-timeout 2 --max-time 5 \
    --header "If-Match: $etag" --header 'Content-Type: application/json' \
    --data-binary "@$desired" --dump-header "$post_headers" --output /dev/null "$localapi_url" ||
    die "Atomic stale Serve hostname repair did not complete or could not be confirmed; rerun convergence"
  [[ -f "$post_headers" && ! -L "$post_headers" ]] ||
    die "Tailscale LocalAPI Serve mutation response headers are invalid"
  post_header_bytes="$(LC_ALL=C wc -c <"$post_headers" | tr -d '[:space:]')"
  [[ "$post_header_bytes" =~ ^[1-9][0-9]{0,4}$ && "$post_header_bytes" -le 16384 ]] &&
    skidbladnir_localapi_response_is_200 "$post_headers" ||
    die "Tailscale LocalAPI did not confirm stale Serve hostname repair with HTTP 200"
)

skidbladnir_configure_serve() (
  set +x
  local tailscale_cli="$1"
  local platform="$2"
  local tailscale_status serve_status post_tailscale_status current_dns_name post_dns_name
  local owned_web_count current_web_count
  case "$platform" in arch | devbox | macos) ;; *) die "unsupported Skidbladnir platform: $platform" ;; esac
  if ! tailscale_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null)"; then
    warn "Skidbladnir Serve pending; sign in to Tailscale, then converge again"
    return
  fi
  tailscale_status="$(printf '%s' "$tailscale_status" | skidbladnir_canonical_single_json)" ||
    die "Tailscale status is invalid"
  printf '%s' "$tailscale_status" | jq -e '
    type == "object" and (.BackendState | type == "string")
  ' >/dev/null || die "Tailscale status is invalid"
  if ! printf '%s' "$tailscale_status" | jq -e '.BackendState == "Running"' >/dev/null; then
    warn "Skidbladnir Serve pending; sign in to Tailscale, then converge again"
    return
  fi
  current_dns_name="$(printf '%s' "$tailscale_status" | skidbladnir_tailscale_current_dns_name)" ||
    die "Tailscale's current DNS hostname is invalid"
  serve_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" serve status --json 2>/dev/null)" ||
    die "Skidbladnir Serve status is unavailable"
  serve_status="$(printf '%s' "$serve_status" | skidbladnir_canonical_single_json)" ||
    die "Skidbladnir Serve status is invalid"
  printf '%s' "$serve_status" | jq -e '
    type == "object" and
    ((.Web // {}) | type == "object") and
    ([((.Web // {}) | to_entries[]) |
      select(.key | endswith(":8443")) |
      ((.value.Handlers // {}) | keys[]) |
      select(. != "/" and . != "/v1")] | length == 0)
  ' >/dev/null || die "Skidbladnir Serve 8443 has an unowned path; remove it explicitly"

  owned_web_count="$(printf '%s' "$serve_status" | jq -er '
    [((.Web // {}) | to_entries[]) | select(.key | endswith(":8443"))] | length
  ')" || die "Skidbladnir Serve status is invalid"
  current_web_count="$(printf '%s' "$serve_status" | jq -er --arg key "$current_dns_name:8443" '
    [((.Web // {}) | to_entries[]) | select(.key == $key)] | length
  ')" || die "Skidbladnir Serve status is invalid"
  if ((owned_web_count > 1 || (owned_web_count == 1 && current_web_count == 0))); then
    printf '%s' "$serve_status" | skidbladnir_serve_config_is_wholly_owned ||
      die "Skidbladnir stale Serve hostnames coexist with unowned state; remove the stale owned mapping explicitly"
    skidbladnir_reconcile_owned_serve_hostnames \
      "$tailscale_cli" "$platform" "$current_dns_name" "$serve_status" || return 1
    post_tailscale_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null)" ||
      die "Tailscale status is unavailable after stale Serve hostname repair"
    post_tailscale_status="$(printf '%s' "$post_tailscale_status" | skidbladnir_canonical_single_json)" ||
      die "Tailscale status is invalid after stale Serve hostname repair"
    post_dns_name="$(printf '%s' "$post_tailscale_status" | skidbladnir_tailscale_current_dns_name)" ||
      die "Tailscale's current DNS hostname is invalid after stale Serve hostname repair"
    [[ "$post_dns_name" == "$current_dns_name" ]] ||
      die "Tailscale's DNS hostname changed during stale Serve hostname repair; converge again"
    serve_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" serve status --json 2>/dev/null)" ||
      die "Skidbladnir Serve status is unavailable after stale-hostname repair"
    serve_status="$(printf '%s' "$serve_status" | skidbladnir_canonical_single_json)" ||
      die "Skidbladnir Serve status is invalid after stale-hostname repair"
    printf '%s' "$serve_status" | skidbladnir_serve_config_is_desired_for_host "$current_dns_name" ||
      die "Atomic stale Serve hostname repair did not produce the canonical current-host mapping"
    return
  fi

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
    TAILSCALE_BE_CLI=1 "$tailscale_cli" serve --yes --https=8443 --set-path=/ off >/dev/null ||
      die "Could not remove the retired Skidbladnir Serve root mapping"
  fi

  # Desired command: tailscale serve --bg --yes --https=8443 --set-path=/v1 http://127.0.0.1:7341/v1
  TAILSCALE_BE_CLI=1 "$tailscale_cli" serve --bg --yes --https=8443 --set-path=/v1 http://127.0.0.1:7341/v1 >/dev/null ||
    die "Could not configure the dedicated Skidbladnir Serve mapping"
)

skidbladnir_activate_linux_service() {
  if [[ "$(loginctl show-user "$(id -un)" -p Linger --value 2>/dev/null || true)" != yes ]]; then
    sudo loginctl enable-linger "$(id -un)"
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now skidbladnir.service
  if ((skidbladnir_changed)); then
    systemctl --user restart skidbladnir.service
  fi
}

skidbladnir_activate_macos_service() {
  local home="$1"
  local label=dev.niels.skidbladnir
  local domain
  local target
  local was_loaded=0
  target="$(skidbladnir_owned_file_target macos "$home" service)"
  domain="gui/$(id -u)"
  launchctl print "$domain/$label" >/dev/null 2>&1 && was_loaded=1
  launchctl enable "$domain/$label"
  if ((was_loaded && skidbladnir_changed)); then
    launchctl bootout "$domain" "$target"
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
  local staging="" archive extracted_members
  local config_dir share_dir state_dir tailscale_cli context
  local owned_name owned_mode owned_source owned_target service_target
  local release_transaction_active=0
  local service_restart_required=0

  require_cmd curl
  require_cmd jq
  require_cmd tar
  home="$(dev_server_home)"
  share_dir="$home/.local/share/skidbladnir"
  skidbladnir_changed=0
  skidbladnir_recover_release_transaction "$platform" "$home"
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
  state_dir="$home/.local/state/skidbladnir"
  skidbladnir_preflight_owned_files "$platform" "$home" "$staging" "$archive"
  skidbladnir_preflight_codex_notify "$home"
  service_target="$(skidbladnir_owned_file_target "$platform" "$home" service)"
  install -d -m 0700 "$config_dir" "$state_dir"
  install -d -m 0755 "$home/.local/bin" "$share_dir"
  install -d -m 0755 "$(dirname "$service_target")"
  for context in personal work work2; do
    install -d -m 0700 "$home/.codex-$context"
  done
  skidbladnir_changed=0

  if [[ ! -e "$config_dir/machine-handle" && ! -L "$config_dir/machine-handle" ]]; then
    "$staging/skidbladnir" machine init --file="$config_dir/machine-handle" >/dev/null
  fi
  skidbladnir_secret_valid "$config_dir/machine-handle" '^mh-[0-9a-f]{32}$' || die "Skidbladnir machine handle is invalid"
  if [[ ! -e "$config_dir/bearer" && ! -L "$config_dir/bearer" ]]; then
    "$staging/skidbladnir" bearer mint --file="$config_dir/bearer" >/dev/null
  fi
  skidbladnir_secret_valid "$config_dir/bearer" '^[A-Za-z0-9_-]{42}[AEIMQUYcgkosw048]$' || die "Skidbladnir bearer is invalid"

  skidbladnir_begin_release_transaction "$platform" "$home"
  release_transaction_active=1
  while read -r owned_name owned_mode; do
    owned_source="$(skidbladnir_owned_file_source \
      "$platform" "$staging" "$archive" "$owned_name")"
    owned_target="$(skidbladnir_owned_file_target "$platform" "$home" "$owned_name")"
    skidbladnir_install_owned "$owned_source" "$owned_target" "$owned_mode"
  done < <(skidbladnir_owned_file_specs)
  skidbladnir_resume_release_activation "$platform" "$home"
  service_restart_required="$skidbladnir_changed"
  if ((service_restart_required)); then
    skidbladnir_mark_release_activation_required "$platform" "$home" "$version" "$source_sha"
  fi
  skidbladnir_commit_release_transaction "$platform" "$home" "$staging" "$archive"
  release_transaction_active=0

  skidbladnir_configure_codex_notify "$home"
  skidbladnir_changed="$service_restart_required"

  if [[ "$platform" == macos ]]; then
    skidbladnir_activate_macos_service "$home"
  else
    skidbladnir_activate_linux_service
  fi
  skidbladnir_clear_release_activation "$platform" "$home"
  tailscale_cli="$(skidbladnir_tailscale_cli)" || {
    warn "Skidbladnir Serve pending; Tailscale CLI is unavailable"
    exit 0
  }
  skidbladnir_configure_serve "$tailscale_cli" "$platform"
)

skidbladnir_doctor() {
  local platform="$1"
  local home config_dir share_dir binary config desired_config pin_line version source_sha archive_sha
  local current_version current_binary_sha current_characters_sha current_release_sha
  local expected_binary_sha expected_characters_sha expected_release_sha bundle bundle_members
  local tailscale_cli tailscale_status tailscale_running current_dns_name
  local tmux_path tmux_version serve_status doctor_xtrace
  local service_source service_target activation_marker
  home="$(dev_server_home)"
  config_dir="$home/.config/skidbladnir"
  share_dir="$home/.local/share/skidbladnir"
  binary="$home/.local/bin/skidbladnir"
  config="$config_dir/host-config.json"
  desired_config="$(skidbladnir_host_config_source "$platform")"
  activation_marker="$(skidbladnir_release_activation_marker "$platform" "$home")"

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
    if [[ ! -e "$activation_marker" && ! -L "$activation_marker" &&
      -f "$service_target" && ! -L "$service_target" ]] &&
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
    if [[ ! -e "$activation_marker" && ! -L "$activation_marker" &&
      -f "$service_target" && ! -L "$service_target" ]] &&
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

  doctor_xtrace=0
  case $- in
  *x*)
    doctor_xtrace=1
    set +x
    ;;
  esac
  tailscale_cli="$(skidbladnir_tailscale_cli 2>/dev/null || true)"
  serve_status=""
  tailscale_status=""
  if [[ -n "$tailscale_cli" ]]; then
    serve_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" serve status --json 2>/dev/null || true)"
    tailscale_status="$(TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null || true)"
  fi
  tailscale_running=0
  if printf '%s' "$tailscale_status" | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
    tailscale_running=1
  fi
  current_dns_name="$(printf '%s' "$tailscale_status" | skidbladnir_tailscale_current_dns_name 2>/dev/null || true)"
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
  elif printf '%s' "$serve_status" | jq -e --arg key "$current_dns_name:8443" '
    type == "object" and .TCP["8443"].HTTPS == true and
    ([((.Web // {}) | to_entries[]) |
      select(.key | endswith(":8443"))] as $owned |
      ($owned | length == 1) and
      ($owned[0].key == $key) and
      ($owned[0].value.Handlers == {"/v1":{"Proxy":"http://127.0.0.1:7341/v1"}}) and
      (((.AllowFunnel // {})[$owned[0].key] // false) == false))
  ' >/dev/null 2>&1; then
    skidbladnir_doctor_pass skidbladnir.serve "private HTTPS 8443 exposes only loopback /v1"
  else
    skidbladnir_doctor_fail skidbladnir.serve "dedicated Serve mapping missing; sign in to Tailscale and converge again"
  fi
  unset tailscale_status current_dns_name serve_status
  if ((doctor_xtrace)); then
    set -x
  fi

  tmux_path="$(jq -er '.tmux.path' "$desired_config" 2>/dev/null || true)"
  tmux_version="$(jq -er '.tmux.version' "$desired_config" 2>/dev/null || true)"
  if [[ -x "$tmux_path" && "$($tmux_path -V 2>/dev/null || true)" == "$tmux_version" ]]; then
    skidbladnir_doctor_pass skidbladnir.tmux "$tmux_version available at the configured path"
  else
    skidbladnir_doctor_fail skidbladnir.tmux "configured tmux path or version differs; run the platform converge command"
  fi

  if ((tailscale_running)); then
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
