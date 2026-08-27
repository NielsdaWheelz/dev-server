#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tests_run=0

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_noop_success() {
  local label="$1"
  shift
  "$@" || fail "$label rejected its supported no-op state"
  tests_run=$((tests_run + 1))
}

# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=lib/dotfiles.sh
source "$repo_dir/lib/dotfiles.sh"
# shellcheck source=lib/packages-arch.sh
source "$repo_dir/lib/packages-arch.sh"

missing_commands=''
command() {
  if [[ "${1:-}" == -v && " $missing_commands " == *" ${2:-} "* ]]; then
    return 1
  fi
  builtin command "$@"
}

uname() { printf 'Darwin\n'; }
assert_noop_success 'XFCE terminal on Darwin' dotfiles_configure_xfce_terminal
assert_noop_success 'Ghostty integration on Darwin' dotfiles_configure_ghostty
assert_noop_success 'XFCE theme on Darwin' dotfiles_configure_xfce_theme
assert_noop_success 'XFCE quality-of-life layer on Darwin' dotfiles_configure_xfce_qol

uname() { printf 'Linux\n'; }
XDG_CURRENT_DESKTOP=GNOME
assert_noop_success 'XFCE terminal outside XFCE' dotfiles_configure_xfce_terminal
assert_noop_success 'XFCE theme outside XFCE' dotfiles_configure_xfce_theme
assert_noop_success 'XFCE quality-of-life layer outside XFCE' dotfiles_configure_xfce_qol

XDG_CURRENT_DESKTOP=XFCE
missing_commands=xfconf-query
assert_noop_success 'XFCE terminal without xfconf' dotfiles_configure_xfce_terminal
assert_noop_success 'XFCE theme without xfconf' dotfiles_configure_xfce_theme
assert_noop_success 'XFCE quality-of-life layer without xfconf' dotfiles_configure_xfce_qol
missing_commands=ghostty
assert_noop_success 'Ghostty integration without Ghostty' dotfiles_configure_ghostty

packages_arch_is_huawei_mach_wx9() { return 1; }
pacman() { return 1; }
XDG_SESSION_TYPE=wayland
assert_noop_success 'X11 touchpad runtime outside X11' packages_arch_apply_touchpad_x11
XDG_SESSION_TYPE=x11
missing_commands=xinput
assert_noop_success 'X11 touchpad runtime without xinput' packages_arch_apply_touchpad_x11
missing_commands=''
xinput() {
  [[ "${1:-}" == list && "${2:-}" == --id-only ]] ||
    fail 'touchpad no-device case reached a mutating xinput command'
}
assert_noop_success 'X11 touchpad runtime without the named device' packages_arch_apply_touchpad_x11
assert_noop_success 'touchpad config on another model' packages_arch_configure_touchpad
assert_noop_success 'declared Docker package absent before doctor' packages_arch_configure_docker
assert_noop_success 'declared zram package absent before doctor' packages_arch_configure_zram
assert_noop_success 'declared firewall package absent before doctor' packages_arch_configure_firewall
assert_noop_success 'declared OpenSSH package absent before doctor' packages_arch_configure_ssh
assert_noop_success 'declared Tailscale package absent before doctor' packages_arch_configure_tailscale
assert_noop_success 'declared reflector package absent before doctor' packages_arch_configure_reflector

missing_commands='cursor dracut eos-update'
assert_noop_success 'declared Cursor command absent before doctor' packages_arch_configure_cursor
assert_noop_success 'declared eos-update command absent before doctor' packages_arch_configure_eos_update
assert_noop_success 'declared dracut command absent before doctor' packages_arch_configure_dracut
packages_arch_systemd_boot_present() { return 1; }
assert_noop_success 'systemd-boot absent on another boot layout' packages_arch_configure_systemd_boot

printf 'PASS: %d platform no-op convergence cases\n' "$tests_run"
