#!/usr/bin/env bash

# Both the installation medium and the installed system see the baseboard.
personal_desktop_board() {
  [[ -r /sys/class/dmi/id/board_vendor && -r /sys/class/dmi/id/board_name ]] &&
    [[ "$(< /sys/class/dmi/id/board_vendor)" == 'Gigabyte Technology Co., Ltd.' ]] &&
    [[ "$(< /sys/class/dmi/id/board_name)" =~ ^Z390\ AORUS\ ULTRA(-CF)?$ ]]
}

personal_desktop_prepare_packages() {
  local repos
  # shellcheck disable=SC2154 # created by workstation before package installation.
  local config="$workstation_declared_stage/pacman.conf"
  repos="$(pacman-conf --repo-list)" || die 'could not read pacman configuration'
  if ! grep -Fxq multilib <<<"$repos"; then
    cp /etc/pacman.conf "$config"
    printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>"$config"
    pacman-conf --config "$config" --repo multilib Server >/dev/null ||
      die 'could not resolve multilib mirrors'
    personal_arch_install_root_file "$config" /etc/pacman.conf 0644
  fi
}

personal_desktop_apply() {
  local home config_dir audio_mutations
  home="$(dev_server_home)"
  for config_dir in alsa-card-profile alsa-card-profile/profile-sets wireplumber wireplumber/wireplumber.conf.d; do
    ensure_directory "$home/.config/$config_dir" 0755
  done
  # shellcheck disable=SC2154 # common.sh counts changes made by install_managed_file.
  audio_mutations=$dev_server_result_mutations
  install_managed_file "$(personal_arch_asset audio/desktop-displays.conf)" \
    "$home/.config/alsa-card-profile/profile-sets/desktop-displays.conf" 0644 desktop.audio
  install_managed_file "$(personal_arch_asset audio/60-desktop-displays.conf)" \
    "$home/.config/wireplumber/wireplumber.conf.d/60-desktop-displays.conf" 0644 desktop.audio
  if ((dev_server_result_mutations != audio_mutations)) && systemctl --user is-active --quiet wireplumber.service; then
    systemctl --user restart wireplumber.service || die 'could not reload desktop audio configuration'
    render_result RESTARTED wireplumber.service
  fi
  personal_arch_plasma_apply kde/powerdevilrc
}
