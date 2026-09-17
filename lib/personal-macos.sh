#!/usr/bin/env bash

personal_macos_desktop_deferred=0

personal_macos_validate_declared_inputs() {
  local asset

  asset="$(dev_server_assets_dir)/dotfiles/ghostty-macos.config"
  [[ -f "$asset" && ! -L "$asset" ]] || die "invalid personal asset: $asset"
}

personal_macos_apply() {
  local home

  personal_macos_validate_declared_inputs
  home="$(dev_server_home)"
  ensure_directory "$home/Library/Application Support/com.mitchellh.ghostty" 0755 || return 1
  install_managed_file "$(dev_server_assets_dir)/dotfiles/ghostty-macos.config" \
    "$home/Library/Application Support/com.mitchellh.ghostty/config.ghostty" \
    0644 desktop.session || return 1
  # Published by the shared atomic installer.
  # shellcheck disable=SC2154
  if [[ "$dev_server_install_status" != 'UP TO DATE' ]]; then
    # Read by workstation_report_deferrals.
    # shellcheck disable=SC2034
    personal_macos_desktop_deferred=1
  fi
}
