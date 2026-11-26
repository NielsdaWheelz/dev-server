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
  # A kernel or microcode update must write the ESP the firmware actually boots.
  [[ "$(findmnt -n --mountpoint /boot -o FSTYPE)" == vfat ]] ||
    die 'mount the desktop EFI system partition at /boot before applying updates'
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
  local user home config_dir audio_mutations
  user="$(id -un)"
  home="$(dev_server_home)"
  if [[ "$(getent passwd "$user" | cut -d: -f7)" != /usr/bin/zsh ]]; then
    sudo usermod -s /usr/bin/zsh "$user"
    render_result CHANGED "$user" 'zsh login shell'
  fi
  ensure_directory "$home/.config/ghostty" 0755
  install_managed_file "$(personal_arch_asset dotfiles/ghostty.config)" "$home/.config/ghostty/config" 0644 desktop.session
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
  personal_arch_install_root_file "$(personal_arch_asset kde/powerdevilrc)" /etc/xdg/powerdevilrc 0644
  personal_arch_ensure_unit NetworkManager.service
  personal_arch_configure_remote_services
  if [[ "$(tailscale status --json | jq -r .BackendState)" != Running ]]; then
    render_result ACTION tailscale 'finish desktop enrollment with sudo tailscale up, then rerun apply'
  fi
  if [[ "$(loginctl show-user "$user" --property=Linger --value)" != yes ]]; then
    sudo loginctl enable-linger "$user"
    render_result CHANGED "$user" 'user services start before login'
  fi
  # Keep the local console available while the first apply is running.
  if ! systemctl is-enabled --quiet plasmalogin.service; then
    sudo systemctl enable plasmalogin.service
    render_result CHANGED plasmalogin.service enabled
  fi
  if [[ "$(systemctl get-default)" != graphical.target ]]; then
    sudo systemctl set-default graphical.target
    render_result CHANGED 'boot target' graphical.target
  fi
  if ! systemctl is-active --quiet plasmalogin.service || personal_arch_reboot_pending; then
    # shellcheck disable=SC2034 # read by workstation_report_deferrals.
    personal_arch_reboot_deferred=1
  fi
}
