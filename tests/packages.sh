#!/usr/bin/env bash
# Globals in this fixture are consumed by sourced production functions.
# shellcheck disable=SC2034
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-packages.XXXXXX")"
tests_run=0

cleanup() {
  rm -rf -- "$fixture"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

assert_empty() {
  [[ ! -s "$1" ]] || fail "$1 is not empty"
}

assert_eq() {
  local want="$1"
  local got="$2"
  local label="$3"

  [[ "$got" == "$want" ]] || fail "$label: got <$got>, want <$want>"
}

file_inode() {
  stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

pass() {
  tests_run=$((tests_run + 1))
}

test_tmux_version_validation_is_locale_invariant() (
  local invalid locale_name valid

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"

  while IFS= read -r locale_name; do
    for valid in 'tmux 3.7c' 'tmux 3.7_c' 'tmux next-3.7'; do
      LC_ALL="$locale_name" dev_server_tmux_version_is_valid "$valid" ||
        fail "valid tmux version was rejected under $locale_name: $valid"
    done
  done < <(locale -a)

  for invalid in '' 'tmux' 'tmux ' $'tmux\t3.7c' ' tmux 3.7c' \
    'tmux 3.7 c' $'tmux 3.7c\nextra'; do
    if dev_server_tmux_version_is_valid "$invalid"; then
      fail "invalid tmux version was accepted: $invalid"
    fi
  done
)

test_arch_native_reconciliation() (
  local calls="$fixture/arch-calls"
  local home="$fixture/arch-home"
  local results="$fixture/arch-results"
  local transaction=0
  : >"$calls"
  : >"$results"
  mkdir -p "$home/.local/state/dev-server/active"
  chmod 0700 "$home/.local/state/dev-server" "$home/.local/state/dev-server/active"
  dev_server_home_dir="$home"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-arch.sh
  source "$repo_dir/lib/packages-arch.sh"
  dev_server_record_active_sha docker.package \
    "$(packages_arch_process_identity docker 1.0-1)"

  pacman() {
    if [[ "$1" == -Q ]]; then
      if (($# == 1)); then
        printf 'docker 1.0-1\ntmux 1.0-1\n'
      else
        printf '%s 1.0-1\n' "$2"
      fi
      return 0
    fi
    printf 'pacman' >>"$calls"
    printf ' %q' "$@" >>"$calls"
    printf '\n' >>"$calls"
    transaction=$((transaction + 1))
  }
  sudo() { "$@"; }
  yay() {
    printf 'yay' >>"$calls"
    printf ' %q' "$@" >>"$calls"
    printf '\n' >>"$calls"
  }
  tmux() {
    [[ "$*" == '-V' ]] && printf 'tmux 1.0\n' && return 0
    return 1
  }
  systemctl() { return 3; }
  docker() { return 1; }
  render_result() {
    printf '%s\n' "$*" >>"$results"
  }

  packages_install
  packages_install

  assert_eq 2 "$(grep -c '^-Syu' <(sed 's/^pacman //' "$calls"))" \
    'full pacman transaction count'
  assert_eq 2 "$(grep -c '^yay -S --needed cursor-bin qogir-icon-theme$' "$calls")" \
    'declared AUR transaction count'
  assert_contains "$calls" 'pacman -Syu --needed arc-gtk-theme-eos atuin base-devel'
  assert_contains "$calls" 'dracut eos-bash-shared eza'
  assert_contains "$calls" 'xorg-xinput yay yazi zoxide zram-generator'
  if grep -Eq -- '(^|[[:space:]])-R|paccache|tldr|reflector\.service|pkgfile-update\.service' "$calls"; then
    fail 'native reconciliation invoked removal or a maintenance one-shot'
  fi
  assert_empty "$results"
)

test_arch_busy_process_deferrals() (
  local calls="$fixture/arch-upgrade-calls"
  local home="$fixture/arch-upgrade-home"
  local results="$fixture/arch-upgrade-results"
  local transaction=0
  : >"$calls"
  : >"$results"
  mkdir -p "$home/.local/state/dev-server/active"
  chmod 0700 "$home/.local/state/dev-server" "$home/.local/state/dev-server/active"
  dev_server_home_dir="$home"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-arch.sh
  source "$repo_dir/lib/packages-arch.sh"

  pacman() {
    if [[ "$1" == -Q ]]; then
      if (($# == 1)); then
        if ((transaction == 0)); then
          printf 'docker 1.0-1\ntmux 1.0-1\n'
        else
          printf 'docker 2.0-1\ntmux 2.0-1\n'
        fi
      elif ((transaction == 0)); then
        printf '%s 1.0-1\n' "$2"
      else
        printf '%s 2.0-1\n' "$2"
      fi
      return 0
    fi
    transaction=1
  }
  sudo() { "$@"; }
  yay() { :; }
  tmux() {
    case "$*" in
    '-V') printf 'tmux 2.0\n' ;;
    'list-sessions') return 0 ;;
    'display-message -p #{version}') printf '1.0\n' ;;
    *) return 1 ;;
    esac
  }
  systemctl() { [[ "$*" == 'is-active --quiet docker.service' ]]; }
  docker() {
    [[ "$*" == '--host unix:///var/run/docker.sock ps -q' ]] || return 1
    printf 'running-container\n'
  }
  render_result() {
    printf '%s\n' "$*" >>"$results"
  }

  packages_install

  assert_contains "$results" 'DEFERRED tmux running sessions keep the prior server until manually restarted'
  assert_contains "$results" 'DEFERRED docker updated daemon has running containers; restart it manually when safe'
  assert_contains "$results" 'UPDATED Arch packages'
  assert_eq 3 "$(wc -l <"$results" | tr -d ' ')" 'package result and busy process deferral count'
)

test_arch_idle_docker_restart() (
  local home="$fixture/arch-idle-home"
  local results="$fixture/arch-idle-results"
  local transaction=0
  local restart_count=0
  : >"$results"
  mkdir -p "$home/.local/state/dev-server/active"
  chmod 0700 "$home/.local/state/dev-server" "$home/.local/state/dev-server/active"
  dev_server_home_dir="$home"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-arch.sh
  source "$repo_dir/lib/packages-arch.sh"

  pacman() {
    if [[ "$1" == -Q ]]; then
      if (($# == 1)); then
        if ((transaction == 0)); then
          printf 'docker 1.0-1\n'
        else
          printf 'docker 2.0-1\n'
        fi
      elif ((transaction == 0)); then
        printf '%s 1.0-1\n' "$2"
      else
        printf '%s 2.0-1\n' "$2"
      fi
      return 0
    fi
    transaction=1
  }
  sudo() { "$@"; }
  yay() { :; }
  tmux() {
    [[ "$*" == '-V' ]] && printf 'tmux 2.0\n' && return 0
    return 1
  }
  docker() { [[ "$*" == '--host unix:///var/run/docker.sock ps -q' ]]; }
  systemctl() {
    case "$*" in
    'is-active --quiet docker.service') return 0 ;;
    'restart docker.service') restart_count=$((restart_count + 1)) ;;
    *) return 1 ;;
    esac
  }
  render_result() { printf '%s\n' "$*" >>"$results"; }

  packages_install

  assert_eq 1 "$restart_count" 'idle Docker restart count'
  assert_contains "$results" 'RESTARTED docker.config updated daemon was idle'
)

test_arch_inactive_docker_activation_is_verified() (
  local active=0 fail_start=0 starts=0
  local failure rc
  local home="$fixture/arch-inactive-docker-home"
  local results="$fixture/arch-inactive-docker-results"
  local first_sha

  : >"$results"
  mkdir -p "$home/.local/state/dev-server/active"
  chmod 0700 "$home/.local/state/dev-server" "$home/.local/state/dev-server/active"
  dev_server_home_dir="$home"
  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-arch.sh
  source "$repo_dir/lib/packages-arch.sh"

  systemctl() {
    case "$*" in
    'is-active --quiet docker.service')
      ((active)) && return 0
      return 3
      ;;
    'start docker.service')
      starts=$((starts + 1))
      ((fail_start == 0)) || return 73
      active=1
      ;;
    *) return 64 ;;
    esac
  }
  sudo() { "$@"; }
  render_result() { printf '%s\n' "$*" >>"$results"; }

  packages_arch_reconcile_docker_activation 1.0-1
  first_sha="$(packages_arch_process_identity docker 1.0-1)"
  dev_server_active_sha_matches docker.package "$first_sha" ||
    fail 'inactive Docker start did not record its verified identity'
  assert_eq 1 "$starts" 'inactive Docker start count'
  assert_contains "$results" 'STARTED docker.config updated daemon was inactive'

  active=0
  fail_start=1
  set +e
  failure="$(packages_arch_reconcile_docker_activation 2.0-1 2>&1)"
  rc=$?
  set -e
  assert_eq 1 "$rc" 'failed inactive Docker start exit'
  assert_eq 'ERROR  could not start docker.service' "$failure" \
    'failed inactive Docker start diagnostic'
  dev_server_active_sha_matches docker.package "$first_sha" ||
    fail 'failed Docker start advanced its active identity'
  ! grep -q '^DEFERRED docker ' "$results" ||
    fail 'failed Docker start was reported as a safe deferral'
)

test_arch_invalid_manifest_is_read_only() (
  local root="$fixture/invalid-manifest"
  local mutation="$fixture/invalid-manifest-mutation"
  mkdir -p "$root/packages"
  dev_server_home_dir="$root/home"
  mkdir -p "$dev_server_home_dir"
  printf 'bat\ninvalid package name\n' >"$root/packages/arch.pacman.txt"
  printf 'cursor-bin\n' >"$root/packages/arch.aur.txt"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  dev_server_root="$root"
  # shellcheck source=lib/packages-arch.sh
  source "$repo_dir/lib/packages-arch.sh"

  pacman() {
    [[ "$1" == -Q ]] && return 1
    : >"$mutation"
  }
  sudo() { "$@"; }
  yay() { : >"$mutation"; }

  if (packages_install) >/dev/null 2>&1; then
    fail 'invalid package manifest was accepted'
  fi
  [[ ! -e "$mutation" ]] || fail 'invalid package manifest mutated native package state'
)

test_macos_native_reconciliation() (
  local calls="$fixture/macos-calls"
  local home="$fixture/macos-home"
  local tailscale_app="$fixture/macos-Tailscale.app"
  local tailscale_cli="$tailscale_app/Contents/MacOS/Tailscale"
  local tailscale_receipt="$tailscale_app/Contents/_MASReceipt/receipt"
  local packages_installed=0
  local tailscale_running=0
  : >"$calls"
  mkdir -p "$home" "$(dirname "$tailscale_cli")" "$(dirname "$tailscale_receipt")"
  printf '#!/bin/sh\n' >"$tailscale_cli"
  printf 'receipt\n' >"$tailscale_receipt"
  chmod 0755 "$tailscale_cli"
  unset HOMEBREW_NO_AUTO_UPDATE
  dev_server_home_dir="$home"
  packages_macos_tailscale_app="$tailscale_app"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-macos.sh
  source "$repo_dir/lib/packages-macos.sh"

  brew() {
    if [[ "$1" == list ]]; then
      ((packages_installed)) && printf 'tmux 3.5\n'
      return 0
    fi
    printf 'brew auto-update=%s' "${HOMEBREW_NO_AUTO_UPDATE:-unset}" >>"$calls"
    printf ' %q' "$@" >>"$calls"
    printf '\n' >>"$calls"
    [[ "$1" != bundle ]] || packages_installed=1
  }
  pgrep() { ((tailscale_running)); }
  open() {
    printf 'open' >>"$calls"
    printf ' %q' "$@" >>"$calls"
    printf '\n' >>"$calls"
    tailscale_running=1
  }
  tmux() {
    [[ "$*" == '-V' ]] && printf 'tmux 3.5\n' && return 0
    return 1
  }
  render_result() {
    printf 'result %s\n' "$*" >>"$calls"
  }

  packages_install
  packages_install

  assert_eq 2 "$(grep -c '^brew auto-update=unset update$' "$calls")" \
    'brew update count'
  assert_eq 2 "$(grep -c '^brew auto-update=1 bundle --file ' "$calls")" \
    'brew bundle count'
  assert_eq 1 "$(grep -Fxc "open -gj $tailscale_app" "$calls")" \
    'Tailscale start count'
  assert_eq 1 "$(grep -c '^result STARTED Tailscale$' "$calls")" \
    'Tailscale result count'
  assert_eq 1 "$(grep -c '^result UPDATED Homebrew packages$' "$calls")" \
    'Homebrew package result count'
)

test_macos_start_requires_postcondition() (
  local home="$fixture/macos-start-home"
  local results="$fixture/macos-start-results"
  local tailscale_app="$fixture/macos-start-Tailscale.app"
  local tailscale_cli="$tailscale_app/Contents/MacOS/Tailscale"
  local tailscale_receipt="$tailscale_app/Contents/_MASReceipt/receipt"
  : >"$results"
  mkdir -p "$home" "$(dirname "$tailscale_cli")" "$(dirname "$tailscale_receipt")"
  printf '#!/bin/sh\n' >"$tailscale_cli"
  printf 'receipt\n' >"$tailscale_receipt"
  chmod 0755 "$tailscale_cli"
  dev_server_home_dir="$home"
  packages_macos_tailscale_app="$tailscale_app"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-macos.sh
  source "$repo_dir/lib/packages-macos.sh"

  brew() {
    [[ "$1" != list ]] || return 0
  }
  pgrep() { return 1; }
  open() { :; }
  sleep() { :; }
  tmux() {
    [[ "$*" == '-V' ]] && printf 'tmux 3.5\n' && return 0
    return 1
  }
  render_result() { printf '%s\n' "$*" >>"$results"; }

  if (packages_install) >/dev/null 2>&1; then
    fail 'macOS package apply accepted a failed Tailscale start'
  fi
  assert_empty "$results"
)

test_macos_tailscale_cli_resolution() (
  local app="$fixture/Tailscale.app"
  local app_cli="$app/Contents/MacOS/Tailscale"
  local receipt="$app/Contents/_MASReceipt/receipt"
  local path_cli="$fixture/bin/tailscale"
  local resolved referent="$fixture/tailscale-referent"

  mkdir -p "$(dirname "$app_cli")" "$(dirname "$receipt")" "$(dirname "$path_cli")"
  printf '#!/bin/sh\n' >"$app_cli"
  printf 'receipt\n' >"$receipt"
  chmod 0755 "$app_cli"
  packages_macos_tailscale_app="$app"
  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/packages-macos.sh
  source "$repo_dir/lib/packages-macos.sh"

  type() {
    [[ "$*" == '-P tailscale' ]] || return 1
    printf '%s\n' "$path_cli"
  }
  resolved="$(packages_macos_tailscale_cli)"
  assert_eq "$app_cli" "$resolved" 'exact App Store Tailscale CLI selection'

  resolved="$(dev_server_tailscale_cli)"
  assert_eq "$path_cli" "$resolved" 'PATH Tailscale CLI selection'

  rm "$receipt"
  if packages_macos_tailscale_cli >/dev/null 2>&1; then
    fail 'Tailscale app without an App Store receipt was accepted'
  fi
  printf 'receipt\n' >"$receipt"

  printf '#!/bin/sh\n' >"$referent"
  chmod 0755 "$referent"
  rm "$app_cli"
  ln -s "$referent" "$app_cli"
  if packages_macos_tailscale_cli >/dev/null 2>&1; then
    fail 'App Store Tailscale CLI accepted a symlink'
  fi
)

test_xfce_idempotence() (
  local gsettings_state="$fixture/gsettings-state"
  local first_output="$fixture/xfce-first-output"
  local second_output="$fixture/xfce-second-output"
  local xfconf_state="$fixture/xfconf-state"
  : >"$gsettings_state"
  : >"$xfconf_state"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"

  state_get() {
    local path="$1"
    local key="$2"
    awk -F '|' -v key="$key" '$1 == key { found = 1; value = $2 } END {
      if (!found) exit 1
      print value
    }' "$path"
  }
  state_put() {
    local path="$1"
    local key="$2"
    local value="$3"
    local temporary="$fixture/state.temporary"
    awk -F '|' -v key="$key" '$1 != key' "$path" >"$temporary"
    printf '%s|%s\n' "$key" "$value" >>"$temporary"
    mv "$temporary" "$path"
  }
  xfconf-query() {
    local channel=''
    local property=''
    local remove=0
    local value=''
    local write=0

    while (($# > 0)); do
      case "$1" in
      -c)
        channel="$2"
        shift 2
        ;;
      -p)
        property="$2"
        shift 2
        ;;
      -r)
        remove=1
        shift
        ;;
      -s)
        value="$2"
        write=1
        shift 2
        ;;
      -n) shift ;;
      -t) shift 2 ;;
      *) fail "unexpected xfconf argument: $1" ;;
      esac
    done
    if ((remove)); then
      local temporary="$fixture/xfconf-remove"
      awk -F '|' -v key="$channel:$property" '$1 != key' "$xfconf_state" >"$temporary"
      mv "$temporary" "$xfconf_state"
      return 0
    fi
    if ((write)); then
      state_put "$xfconf_state" "$channel:$property" "$value"
    else
      state_get "$xfconf_state" "$channel:$property"
    fi
  }
  gsettings() {
    local operation="$1"
    local schema="$2"
    local key="$3"
    case "$operation" in
    get) state_get "$gsettings_state" "$schema:$key" ;;
    set) state_put "$gsettings_state" "$schema:$key" "$4" ;;
    *) fail "unexpected gsettings operation: $operation" ;;
    esac
  }
  personal_arch_brightness_floor() { return 1; }

  personal_arch_configure_xfce >"$first_output"
  personal_arch_configure_xfce >"$second_output"

  assert_contains "$first_output" 'CHANGED  XFCE policy'
  assert_empty "$second_output"
  assert_eq balanced \
    "$(state_get "$xfconf_state" 'xfce4-power-manager:/xfce4-power-manager/profile-on-ac')" \
    'XFCE AC profile'
  assert_eq workspace_4_key \
    "$(state_get "$xfconf_state" 'xfce4-keyboard-shortcuts:/xfwm4/custom/<Super>4')" \
    'XFCE workspace shortcut'
)

test_unit_activation_is_exact() (
  local active=0
  local calls="$fixture/unit-calls"
  local enabled=0
  local output="$fixture/unit-output"
  : >"$calls"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"

  systemctl() {
    case "$1" in
    is-enabled) ((enabled)) ;;
    is-active) ((active)) ;;
    enable)
      enabled=1
      printf 'enable %s\n' "$2" >>"$calls"
      ;;
    start)
      active=1
      printf 'start %s\n' "$2" >>"$calls"
      ;;
    *) fail "unexpected systemctl operation: $*" ;;
    esac
  }
  sudo() { "$@"; }

  personal_arch_ensure_unit reflector.timer >"$output"
  personal_arch_ensure_unit reflector.timer >>"$output"

  assert_eq $'enable reflector.timer\nstart reflector.timer' \
    "$(<"$calls")" 'unit activation calls'
  assert_eq $'CHANGED  reflector.timer: enabled\nSTARTED  reflector.timer' \
    "$(<"$output")" 'unit activation results'
)

test_active_identity() (
  local desired_sha=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef
  local home="$fixture/active-home"

  mkdir -p "$home/.local/state/dev-server/active"
  export dev_server_home_dir="$home"
  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"

  dev_server_record_active_sha zram "$desired_sha"
  dev_server_active_sha_matches zram "$desired_sha" ||
    fail 'recorded zram identity did not match'
  assert_eq 600 "$(file_mode "$home/.local/state/dev-server/active/zram.sha256")" \
    'active identity mode'
  dev_server_record_active_sha zram "$desired_sha"
  dev_server_active_sha_matches zram "$desired_sha" ||
    fail 'idempotent zram identity did not match'
)

test_root_boot_identity_uses_privileged_metadata() (
  local calls="$fixture/boot-metadata-calls"
  : >"$calls"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"

  awk() {
    [[ "$*" == '$1 == "btime" { print $2; exit } /proc/stat' ]] || return 64
    printf '100\n'
  }
  stat() {
    [[ "$*" == "-c %Y /efi/loader/loader.conf" ]] || return 64
    printf '0\n'
  }
  sudo() {
    printf '%s\n' "$*" >>"$calls"
    [[ "$1" == -- ]] || return 64
    shift
    "$@"
  }

  personal_arch_boot_consumed root /efi/loader/loader.conf ||
    fail 'root-managed boot metadata was not compared'
  assert_eq '-- stat -c %Y /efi/loader/loader.conf' "$(<"$calls")" \
    'root-managed boot metadata privilege'
)

test_absent_desktop_needs_no_touchpad_deferral() (
  local results="$fixture/touchpad-session-results"
  : >"$results"

  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"

  personal_arch_touchpad_runtime_configured() { return 1; }
  personal_arch_apply_touchpad_runtime() { return 1; }
  render_result() { printf '%s\n' "$*" >>"$results"; }
  pgrep() { return 1; }

  personal_arch_reconcile_touchpad_runtime 0
  ! has_change desktop.session ||
    fail 'absent desktop was treated as a pending activation'
  assert_empty "$results"

  pgrep() { return 0; }
  personal_arch_reconcile_touchpad_runtime 0
  has_change desktop.session ||
    fail 'running desktop did not retain its activation deferral'
)

test_boot_consumed_zram_seals_without_reload() (
  local asset_root="$fixture/zram-assets"
  local daemon_reloads=0 starts=0
  local output="$fixture/zram-boot-consumed-output"
  local desired_sha home="$fixture/zram-retry-home"

  mkdir -p "$asset_root/assets/systemd" "$home/.local/state/dev-server/active"
  chmod 0700 "$home/.local/state/dev-server" "$home/.local/state/dev-server/active"
  printf '%s\n' '[zram0]' 'zram-size = ram / 2' \
    >"$asset_root/assets/systemd/zram-generator.conf"
  dev_server_home_dir="$home"
  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"
  dev_server_root="$asset_root"
  desired_sha="$(dev_server_sha256 "$asset_root/assets/systemd/zram-generator.conf")"

  personal_arch_boot_consumed() { return 0; }
  systemctl() {
    case "$*" in
    'daemon-reload') daemon_reloads=$((daemon_reloads + 1)) ;;
    'is-active --quiet systemd-zram-setup@zram0.service') return 0 ;;
    'start systemd-zram-setup@zram0.service') starts=$((starts + 1)) ;;
    *) return 64 ;;
    esac
  }
  sudo() { "$@"; }

  personal_arch_configure_zram >"$output"
  dev_server_active_sha_matches zram "$desired_sha" ||
    fail 'boot-consumed zram did not record live desired state'
  assert_eq 0 "$daemon_reloads" 'boot-consumed zram daemon reload count'
  assert_eq 0 "$starts" 'boot-consumed zram unnecessary start count'
  assert_empty "$output"
)

test_cursor_key_is_atomic_and_narrow() (
  local extension_version=1.1.13
  local home="$fixture/cursor-home"
  local inode
  local referent="$fixture/cursor-referent"
  local settings

  install -d -m 0755 "$home/.config/Cursor/User"
  settings="$home/.config/Cursor/User/settings.json"
  printf '%s\n' \
    '{"editor.fontSize":14,"remote.SSH.remotePlatform":{"old":"linux"}}' \
    >"$settings"
  export dev_server_home_dir="$home"
  # shellcheck source=lib/common.sh
  source "$repo_dir/lib/common.sh"
  # shellcheck source=lib/personal-arch.sh
  source "$repo_dir/lib/personal-arch.sh"

  cursor() {
    case "$*" in
    '--list-extensions --show-versions')
      printf 'anysphere.remote-ssh@%s\n' "$extension_version"
      ;;
    '--install-extension anysphere.remote-ssh@1.1.14 --force')
      extension_version=1.1.14
      ;;
    *) return 1 ;;
    esac
  }

  personal_arch_configure_cursor >/dev/null
  assert_eq 1.1.14 "$extension_version" 'Cursor extension version'
  jq -e '
    ."editor.fontSize" == 14 and
    ."remote.SSH.remotePlatform" == {
      "dev-server": "linux",
      "macbook": "macOS"
    }
  ' "$settings" >/dev/null || fail 'Cursor key rewrite widened its ownership'
  inode="$(file_inode "$settings")"
  personal_arch_configure_cursor >/dev/null
  assert_eq "$inode" "$(file_inode "$settings")" \
    'unchanged Cursor settings inode'

  printf 'preserve\n' >"$referent"
  rm "$settings"
  ln -s "$referent" "$settings"
  if (personal_arch_configure_cursor) >/dev/null 2>&1; then
    fail 'Cursor key rewrite accepted a symlink target'
  fi
  assert_eq preserve "$(<"$referent")" 'Cursor symlink referent preservation'

  rm "$settings"
  printf '%s\n' \
    '{"editor.fontSize":14,"editor.fontSize":15}' >"$settings"
  extension_version=1.1.13
  inode="$(file_inode "$settings")"
  if (personal_arch_configure_cursor) >/dev/null 2>&1; then
    fail 'Cursor accepted duplicate settings keys'
  fi
  assert_eq 1.1.13 "$extension_version" \
    'invalid Cursor settings extension mutation guard'
  assert_eq "$inode" "$(file_inode "$settings")" \
    'invalid Cursor settings inode preservation'
  assert_eq '{"editor.fontSize":14,"editor.fontSize":15}' \
    "$(<"$settings")" 'invalid Cursor settings byte preservation'
)

test_static_policy() {
  [[ ! -e "$repo_dir/packages/arch.remove.txt" ]] ||
    fail 'automatic Arch removal manifest remains'
  ! grep -Eiq 'tailscale' "$repo_dir/packages/Brewfile" ||
    fail 'externally owned Tailscale entered the Brewfile'
  ! grep -Fqx eos-apps-info "$repo_dir/packages/arch.pacman.txt" ||
    fail 'retired EndeavourOS onboarding package remains declared'
  LC_ALL=C sort -cu "$repo_dir/packages/arch.pacman.txt" >/dev/null ||
    fail 'pacman manifest is not sorted and unique'
  LC_ALL=C sort -cu "$repo_dir/packages/arch.aur.txt" >/dev/null ||
    fail 'AUR manifest is not sorted and unique'
  grep -Fqx arc-gtk-theme-eos "$repo_dir/packages/arch.pacman.txt" ||
    fail 'Arc is not sourced from the native EndeavourOS repository'
  ! grep -Fqx arc-gtk-theme "$repo_dir/packages/arch.aur.txt" ||
    fail 'stale Arc AUR build remains declared'
  if grep -Eq 'pacman[[:space:]]+-R|paccache[[:space:]]+-|tldr[[:space:]]+--update|systemctl[[:space:]]+start[[:space:]]+(reflector|pkgfile-update)' \
    "$repo_dir/lib/packages-arch.sh" "$repo_dir/lib/personal-arch.sh"; then
    fail 'automatic removal or per-apply maintenance one-shot remains'
  fi
  assert_contains "$repo_dir/lib/personal-arch.sh" 'fmask=0137'
  assert_contains "$repo_dir/lib/personal-arch.sh" '/efi/loader/loader.conf 0640'
  if grep -Fq '[[ -d /efi/loader ]]' "$repo_dir/lib/personal-arch.sh"; then
    fail 'unprivileged Arch preflight traverses the root-only ESP'
  fi
  assert_eq 'TerminalEmulator=ghostty' \
    "$(<"$repo_dir/assets/dotfiles/xfce4-helpers.rc")" \
    'fully owned XFCE helper'
  assert_contains "$repo_dir/lib/personal-arch.sh" \
    'dotfiles/xfce4-helpers.rc'
  assert_contains "$repo_dir/lib/personal-arch.sh" \
    'anysphere.remote-ssh@1.1.14 --force'
  if grep -Eq 'personal_arch_write_ghostty_helper|personal_arch_disable_user_unit|xfce4-clipman\.desktop|xfce4-clipman\.service|gammastep\.service|app-com\.mitchellh\.ghostty\.service' \
    "$repo_dir/lib/personal-arch.sh"; then
    fail 'runtime legacy cleanup or partial XFCE helper ownership remains'
  fi
  if grep -Eq 'hostname([[:space:]]+-s)?' "$repo_dir/lib/personal-arch.sh"; then
    fail 'owned Arch hardware identity depends on a mutable hostname'
  fi
}

test_tmux_version_validation_is_locale_invariant
pass
test_arch_native_reconciliation
pass
test_arch_busy_process_deferrals
pass
test_arch_idle_docker_restart
pass
test_arch_inactive_docker_activation_is_verified
pass
test_arch_invalid_manifest_is_read_only
pass
test_macos_native_reconciliation
pass
test_macos_start_requires_postcondition
pass
test_macos_tailscale_cli_resolution
pass
test_xfce_idempotence
pass
test_unit_activation_is_exact
pass
test_active_identity
pass
test_root_boot_identity_uses_privileged_metadata
pass
test_absent_desktop_needs_no_touchpad_deferral
pass
test_boot_consumed_zram_seals_without_reload
pass
test_cursor_key_is_atomic_and_narrow
pass
test_static_policy
pass

printf 'PASS: %d package/personal contract tests\n' "$tests_run"
