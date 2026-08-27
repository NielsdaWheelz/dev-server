#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

packages_arch_pacman_file() {
  printf '%s/packages/arch.pacman.txt\n' "$dev_server_root"
}

packages_arch_aur_file() {
  printf '%s/packages/arch.aur.txt\n' "$dev_server_root"
}

packages_arch_remove_file() {
  printf '%s/packages/arch.remove.txt\n' "$dev_server_root"
}

packages_non_comment_lines() {
  sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$1"
}

packages_arch_aur_helper() {
  local helper

  for helper in paru yay; do
    if command -v "$helper" >/dev/null 2>&1; then
      printf '%s\n' "$helper"
      return
    fi
  done

  return 1
}

packages_arch_package_installed_exact() {
  [[ "$(pacman -Qq "$1" 2>/dev/null || true)" == "$1" ]]
}

packages_arch_reboot_pending() {
  [[ ! -d "/usr/lib/modules/$(uname -r)" ]]
}

packages_arch_is_huawei_mach_wx9() {
  [[ -r /sys/class/dmi/id/sys_vendor ]] &&
    [[ -r /sys/class/dmi/id/product_name ]] &&
    [[ "$(</sys/class/dmi/id/sys_vendor)" == "HUAWEI" ]] &&
    [[ "$(</sys/class/dmi/id/product_name)" == "MACH-WX9" ]]
}

packages_arch_is_intel_cpu() {
  grep -Eqm1 '^vendor_id[[:space:]]*:?[[:space:]]+GenuineIntel$' /proc/cpuinfo
}

packages_arch_touchpad_config_source() {
  printf '%s/assets/xorg/90-dev-server-huawei-touchpad.conf\n' "$dev_server_root"
}

packages_arch_touchpad_config_dest() {
  printf '/etc/X11/xorg.conf.d/90-dev-server-huawei-touchpad.conf\n'
}

packages_arch_zram_config_source() {
  printf '%s/assets/systemd/zram-generator.conf\n' "$dev_server_root"
}

packages_arch_zram_config_dest() {
  printf '/etc/systemd/zram-generator.conf\n'
}

packages_arch_eos_update_config_source() {
  printf '%s/assets/endeavouros/eos-update.conf\n' "$dev_server_root"
}

packages_arch_eos_update_config_dest() {
  printf '/etc/eos-update.conf\n'
}

packages_arch_dracut_config_source() {
  printf '%s/assets/dracut/90-dev-server.conf\n' "$dev_server_root"
}

packages_arch_dracut_config_dest() {
  printf '/etc/dracut.conf.d/90-dev-server.conf\n'
}

packages_arch_systemd_boot_config_source() {
  printf '%s/assets/systemd-boot/loader.conf\n' "$dev_server_root"
}

packages_arch_systemd_boot_config_dest() {
  printf '/efi/loader/loader.conf\n'
}

packages_arch_systemd_boot_present() {
  [[ -d /efi/loader ]]
}

packages_arch_reflector_config_source() {
  printf '%s/assets/reflector/reflector.conf\n' "$dev_server_root"
}

packages_arch_reflector_config_dest() {
  printf '/etc/xdg/reflector/reflector.conf\n'
}

packages_arch_apply_touchpad_x11() {
  local device motion_points_string motion_step source
  local -a motion_points

  [[ "${XDG_SESSION_TYPE:-}" == "x11" ]] || return 0
  command -v xinput >/dev/null 2>&1 || return 0
  device="$(xinput list --id-only 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null || true)"
  [[ -n "$device" ]] || return 0

  source="$(packages_arch_touchpad_config_source)"
  motion_points_string="$(awk -F '"' '$2 == "AccelPointsMotion" { print $4; exit }' "$source")"
  motion_step="$(awk -F '"' '$2 == "AccelStepMotion" { print $4; exit }' "$source")"
  read -r -a motion_points <<<"$motion_points_string"
  [[ "${#motion_points[@]}" -ge 2 && -n "$motion_step" ]] ||
    die "invalid touchpad motion curve in $source"

  xinput set-prop --type=float --format=32 "$device" \
    'libinput Accel Custom Fallback Points' 0.0 1.0
  xinput set-prop "$device" 'libinput Accel Custom Fallback Step' 1.0
  xinput set-prop --type=float --format=32 "$device" \
    'libinput Accel Custom Motion Points' "${motion_points[@]}"
  xinput set-prop "$device" 'libinput Accel Custom Motion Step' "$motion_step"
  xinput set-prop --type=float --format=32 "$device" \
    'libinput Accel Custom Scroll Points' 0.0 1.0
  xinput set-prop "$device" 'libinput Accel Custom Scroll Step' 1.0
  xinput set-prop "$device" 'libinput Accel Profile Enabled' 0 0 1
  xinput set-prop "$device" 'libinput Click Method Enabled' 0 1
  xinput set-prop "$device" 'libinput Disable While Typing Enabled' 1
  xinput set-prop "$device" 'libinput Horizontal Scroll Enabled' 1
  xinput set-prop "$device" 'libinput Natural Scrolling Enabled' 1
  xinput set-prop "$device" 'libinput Scroll Method Enabled' 1 0 0
  xinput set-prop "$device" 'libinput Scrolling Pixel Distance' 15
  xinput set-prop "$device" 'libinput Tapping Enabled' 1
  xinput set-prop "$device" 'libinput Tapping Button Mapping Enabled' 1 0
  xinput set-prop "$device" 'libinput Tapping Drag Enabled' 1
  xinput set-prop "$device" 'libinput Tapping Drag Lock Enabled' 0
}

packages_arch_configure_touchpad() {
  local source

  packages_arch_is_huawei_mach_wx9 || return 0
  source="$(packages_arch_touchpad_config_source)"
  [[ -f "$source" ]] || die "missing touchpad config: $source"
  sudo install -D -m 0644 "$source" "$(packages_arch_touchpad_config_dest)"
  packages_arch_apply_touchpad_x11
}

packages_arch_configure_docker() {
  local user

  pacman -Q docker >/dev/null 2>&1 || return 0
  user="$(id -un)"
  sudo systemctl enable docker.service
  if ! sudo systemctl start docker.service; then
    if packages_arch_reboot_pending; then
      warn "Docker is enabled but cannot start until the pending kernel update is activated by a reboot"
    else
      die "failed to start Docker"
    fi
  fi
  if ! id -nG "$user" | tr ' ' '\n' | grep -Fqx docker; then
    log "adding $user to the docker group; log out and back in to activate it"
    sudo usermod -aG docker "$user"
  fi
}

packages_arch_remove_packages() {
  local declared_packages=()
  local installed_packages=()
  local package

  mapfile -t declared_packages < <(packages_non_comment_lines "$(packages_arch_remove_file)")
  for package in "${declared_packages[@]}"; do
    packages_arch_package_installed_exact "$package" && installed_packages+=("$package")
  done

  if ((${#installed_packages[@]} > 0)); then
    sudo pacman -Rns --noconfirm "${installed_packages[@]}"
  fi
}

packages_arch_configure_zram() {
  local source

  pacman -Q zram-generator >/dev/null 2>&1 || return 0
  source="$(packages_arch_zram_config_source)"
  [[ -f "$source" ]] || die "missing zram config: $source"
  sudo install -D -m 0644 "$source" "$(packages_arch_zram_config_dest)"
  sudo systemctl daemon-reload
  if ! sudo systemctl start systemd-zram-setup@zram0.service; then
    if packages_arch_reboot_pending; then
      warn "zram is configured but cannot start until the pending kernel update is activated by a reboot"
    else
      die "failed to start zram"
    fi
  fi
}

packages_arch_configure_firewall() {
  pacman -Q firewalld >/dev/null 2>&1 || return 0
  sudo systemctl enable --now firewalld.service
  if sudo firewall-cmd --quiet --permanent --zone=public --query-service=ssh; then
    sudo firewall-cmd --quiet --permanent --zone=public --remove-service=ssh
    sudo firewall-cmd --quiet --reload
  fi
}

packages_arch_configure_ssh() {
  pacman -Q openssh >/dev/null 2>&1 || return 0
  sudo systemctl enable --now sshd.service
}

packages_arch_configure_tailscale() {
  pacman -Q tailscale >/dev/null 2>&1 || return 0
  sudo systemctl enable tailscaled.service
  if ! sudo systemctl start tailscaled.service; then
    if packages_arch_reboot_pending; then
      warn "Tailscale is enabled but cannot start until the pending kernel update is activated by a reboot"
    else
      die "failed to start Tailscale"
    fi
  fi
}

packages_arch_configure_cursor() {
  local home
  local settings_dir
  local settings_file
  local settings_tmp

  command -v cursor >/dev/null 2>&1 || return 0
  cursor --install-extension anysphere.remote-ssh --force

  home="$(dev_server_home)"
  settings_dir="$home/.config/Cursor/User"
  settings_file="$settings_dir/settings.json"
  install -d -m 0755 "$settings_dir"
  settings_tmp="$(mktemp "$settings_dir/.settings.json.XXXXXX")"
  if [[ -s "$settings_file" ]]; then
    jq '."remote.SSH.remotePlatform" = ((."remote.SSH.remotePlatform" // {}) + {
      "dev-server": "linux",
      "macbook": "macOS"
    })' "$settings_file" >"$settings_tmp"
  else
    jq -n '{
      "remote.SSH.remotePlatform": {
        "dev-server": "linux",
        "macbook": "macOS"
      }
    }' >"$settings_tmp"
  fi
  chmod 0644 "$settings_tmp"
  mv "$settings_tmp" "$settings_file"
}

packages_arch_configure_reflector() {
  local source

  pacman -Q reflector >/dev/null 2>&1 || return 0
  source="$(packages_arch_reflector_config_source)"
  [[ -f "$source" ]] || die "missing reflector config: $source"
  sudo install -D -m 0644 "$source" "$(packages_arch_reflector_config_dest)"
  sudo systemctl start reflector.service
  sudo systemctl enable --now reflector.timer
}

packages_arch_configure_eos_update() {
  local source

  command -v eos-update >/dev/null 2>&1 || return 0
  source="$(packages_arch_eos_update_config_source)"
  [[ -f "$source" ]] || die "missing eos-update config: $source"
  sudo install -D -m 0644 "$source" "$(packages_arch_eos_update_config_dest)"
}

packages_arch_configure_dracut() {
  local source

  command -v dracut >/dev/null 2>&1 || return 0
  source="$(packages_arch_dracut_config_source)"
  [[ -f "$source" ]] || die "missing dracut config: $source"
  sudo install -D -m 0644 "$source" "$(packages_arch_dracut_config_dest)"
}

packages_arch_configure_systemd_boot() {
  local source

  packages_arch_systemd_boot_present || return 0
  source="$(packages_arch_systemd_boot_config_source)"
  [[ -f "$source" ]] || die "missing systemd-boot config: $source"
  sudo install -D -m 0644 "$source" "$(packages_arch_systemd_boot_config_dest)"
}

packages_arch_configure_maintenance() {
  if pacman -Q fwupd >/dev/null 2>&1; then
    sudo systemctl enable --now fwupd-refresh.timer
  fi

  if pacman -Q smartmontools >/dev/null 2>&1; then
    sudo systemctl enable --now smartd.service
  fi

  if pacman -Q thermald >/dev/null 2>&1 && packages_arch_is_intel_cpu; then
    sudo systemctl enable --now thermald.service
  fi

  if pacman -Q pkgfile >/dev/null 2>&1; then
    sudo systemctl start pkgfile-update.service
    sudo systemctl enable --now pkgfile-update.timer
  fi

  if pacman -Q pacman-contrib >/dev/null 2>&1; then
    sudo systemctl enable --now paccache.timer
    sudo paccache -ruk0
  fi

  if command -v tldr >/dev/null 2>&1; then
    tldr --update || warn "failed to refresh the tealdeer page cache"
  fi
}

packages_install() {
  local pacman_packages=()
  local pacman_arguments=(-Syu --needed)
  local aur_packages=()
  local aur_helper

  require_cmd pacman
  require_cmd sudo
  mapfile -t pacman_packages < <(packages_non_comment_lines "$(packages_arch_pacman_file)")
  mapfile -t aur_packages < <(packages_non_comment_lines "$(packages_arch_aur_file)")

  packages_arch_configure_dracut
  packages_arch_remove_packages

  if ((${#pacman_packages[@]} > 0)); then
    if [[ -x /usr/bin/tmux && "$(/usr/bin/tmux -V)" == 'tmux 3.7c' ]]; then
      pacman_arguments+=(--ignore tmux)
    fi
    sudo pacman "${pacman_arguments[@]}" "${pacman_packages[@]}"
  fi

  if ((${#aur_packages[@]} > 0)); then
    aur_helper="$(packages_arch_aur_helper)" || die "AUR packages declared but neither paru nor yay is installed"
    "$aur_helper" -S --needed "${aur_packages[@]}"
  fi

  packages_arch_configure_touchpad
  packages_arch_configure_docker
  packages_arch_configure_zram
  packages_arch_configure_firewall
  packages_arch_configure_tailscale
  packages_arch_configure_ssh
  packages_arch_configure_cursor
  packages_arch_configure_reflector
  packages_arch_configure_eos_update
  packages_arch_configure_systemd_boot
  packages_arch_configure_maintenance
}

packages_doctor() {
  local pacman_packages=()
  local aur_packages=()
  local removed_packages=()
  local missing_packages=()
  local present_packages=()
  local package

  if command -v pacman >/dev/null 2>&1; then
    doctor_pass package.pacman "pacman present"
  else
    doctor_fail package.pacman "pacman missing"
    return
  fi

  mapfile -t pacman_packages < <(packages_non_comment_lines "$(packages_arch_pacman_file)")
  for package in "${pacman_packages[@]}"; do
    pacman -Q "$package" >/dev/null 2>&1 || missing_packages+=("$package")
  done
  if ((${#missing_packages[@]} == 0)); then
    doctor_pass package.manifest "${#pacman_packages[@]} declared repository packages installed"
  else
    doctor_fail package.manifest "missing packages: ${missing_packages[*]}"
  fi

  mapfile -t removed_packages < <(packages_non_comment_lines "$(packages_arch_remove_file)")
  for package in "${removed_packages[@]}"; do
    packages_arch_package_installed_exact "$package" && present_packages+=("$package")
  done
  if ((${#present_packages[@]} == 0)); then
    doctor_pass package.removals "declared unwanted packages absent"
  else
    doctor_fail package.removals "unwanted packages installed: ${present_packages[*]}"
  fi

  mapfile -t aur_packages < <(packages_non_comment_lines "$(packages_arch_aur_file)")
  if ((${#aur_packages[@]} > 0)); then
    missing_packages=()
    for package in "${aur_packages[@]}"; do
      pacman -Q "$package" >/dev/null 2>&1 || missing_packages+=("$package")
    done
    if ((${#missing_packages[@]} == 0)); then
      doctor_pass package.aur "${#aur_packages[@]} declared AUR packages installed"
    else
      doctor_fail package.aur "missing packages: ${missing_packages[*]}"
    fi

    if packages_arch_aur_helper >/dev/null; then
      doctor_pass package.aur-helper "$(packages_arch_aur_helper) present"
    else
      doctor_fail package.aur-helper "neither paru nor yay is installed"
    fi
  fi

  if pacman -Q docker >/dev/null 2>&1; then
    if systemctl is-enabled --quiet docker.service && systemctl is-active --quiet docker.service; then
      doctor_pass package.docker-service "Docker service enabled and active"
    elif systemctl is-enabled --quiet docker.service && packages_arch_reboot_pending; then
      doctor_warn package.docker-service "Docker enabled; reboot into the installed kernel before use"
    else
      doctor_fail package.docker-service "Docker service is not enabled and active"
    fi

    if id -nG "$(id -un)" | tr ' ' '\n' | grep -Fqx docker; then
      doctor_pass package.docker-group "$(id -un) is enrolled in the docker group"
    else
      doctor_fail package.docker-group "$(id -un) is not enrolled in the docker group"
    fi
  fi

  if pacman -Q zram-generator >/dev/null 2>&1; then
    if [[ -f "$(packages_arch_zram_config_dest)" ]] &&
      cmp -s "$(packages_arch_zram_config_source)" "$(packages_arch_zram_config_dest)"; then
      doctor_pass package.zram-config "8 GiB zram policy installed"
    else
      doctor_fail package.zram-config "zram policy is not installed"
    fi

    if swapon --show | awk '$1 == "/dev/zram0" { found=1 } END { exit !found }'; then
      doctor_pass package.zram-runtime "zram swap active"
    elif packages_arch_reboot_pending; then
      doctor_warn package.zram-runtime "zram configured; reboot into the installed kernel to activate"
    else
      doctor_fail package.zram-runtime "zram swap is not active"
    fi
  fi

  if pacman -Q firewalld >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld.service &&
      ! firewall-cmd --quiet --zone=public --query-service=ssh; then
      doctor_pass package.firewall "firewalld active without public SSH permission"
    else
      doctor_fail package.firewall "firewalld inactive or public SSH permission present"
    fi
  fi

  if pacman -Q openssh >/dev/null 2>&1; then
    if systemctl is-enabled --quiet sshd.service &&
      systemctl is-active --quiet sshd.service; then
      doctor_pass package.ssh "OpenSSH enabled for fixed tailnet operator access"
    else
      doctor_fail package.ssh "OpenSSH is not enabled and active"
    fi
  fi

  if pacman -Q tailscale >/dev/null 2>&1; then
    if systemctl is-enabled --quiet tailscaled.service &&
      systemctl is-active --quiet tailscaled.service; then
      doctor_pass package.tailscale-service "Tailscale service enabled and active"
    elif systemctl is-enabled --quiet tailscaled.service && packages_arch_reboot_pending; then
      doctor_warn package.tailscale-service "Tailscale enabled; reboot into the installed kernel before use"
    else
      doctor_fail package.tailscale-service "Tailscale service is not enabled and active"
    fi

    if tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
      doctor_pass package.tailscale-session "Tailscale connected to a tailnet"
    elif packages_arch_reboot_pending; then
      doctor_warn package.tailscale-session "Tailscale runtime verification pending until after reboot"
    else
      doctor_fail package.tailscale-session "Tailscale is not connected; run: sudo tailscale up"
    fi
  fi

  if pacman -Q cursor-bin >/dev/null 2>&1; then
    if cursor --list-extensions 2>/dev/null | grep -Fqx anysphere.remote-ssh; then
      doctor_pass package.cursor-remote-ssh "Cursor Remote SSH extension installed"
    else
      doctor_fail package.cursor-remote-ssh "Cursor Remote SSH extension missing"
    fi

    if jq -e '
      ."remote.SSH.remotePlatform"."dev-server" == "linux" and
      ."remote.SSH.remotePlatform".macbook == "macOS"
    ' "$(dev_server_home)/.config/Cursor/User/settings.json" >/dev/null 2>&1; then
      doctor_pass package.cursor-remote-hosts "Cursor remote platforms configured"
    else
      doctor_fail package.cursor-remote-hosts "Cursor remote platforms are not configured"
    fi
  fi

  if pacman -Q reflector >/dev/null 2>&1; then
    if [[ -f "$(packages_arch_reflector_config_dest)" ]] &&
      cmp -s "$(packages_arch_reflector_config_source)" "$(packages_arch_reflector_config_dest)" &&
      systemctl is-enabled --quiet reflector.timer &&
      systemctl is-active --quiet reflector.timer; then
      doctor_pass package.reflector "regional health-ranked mirror policy and weekly timer active"
    else
      doctor_fail package.reflector "reflector policy or weekly timer is not active"
    fi
  fi

  if pacman -Q fwupd >/dev/null 2>&1; then
    if systemctl is-enabled --quiet fwupd-refresh.timer &&
      systemctl is-active --quiet fwupd-refresh.timer; then
      doctor_pass package.firmware-refresh "fwupd metadata refresh timer active"
    else
      doctor_fail package.firmware-refresh "fwupd metadata refresh timer is not active"
    fi
  fi

  if pacman -Q smartmontools >/dev/null 2>&1; then
    if systemctl is-enabled --quiet smartd.service &&
      systemctl is-active --quiet smartd.service; then
      doctor_pass package.smart "SMART disk monitoring active"
    else
      doctor_fail package.smart "SMART disk monitoring is not active"
    fi
  fi

  if pacman -Q thermald >/dev/null 2>&1 && packages_arch_is_intel_cpu; then
    if systemctl is-enabled --quiet thermald.service &&
      systemctl is-active --quiet thermald.service; then
      doctor_pass package.thermal-management "Intel thermald service enabled and active"
    else
      doctor_fail package.thermal-management "Intel thermald service is not enabled and active"
    fi
  fi

  if pacman -Q pkgfile >/dev/null 2>&1; then
    if systemctl is-enabled --quiet pkgfile-update.timer &&
      systemctl is-active --quiet pkgfile-update.timer &&
      pkgfile -b sh >/dev/null 2>&1; then
      doctor_pass package.pkgfile "pkgfile database present and daily refresh timer active"
    else
      doctor_fail package.pkgfile "pkgfile database or daily refresh timer is not active"
    fi
  fi

  if pacman -Q pacman-contrib >/dev/null 2>&1; then
    if systemctl is-enabled --quiet paccache.timer &&
      systemctl is-active --quiet paccache.timer; then
      doctor_pass package.cache-maintenance "weekly package-cache cleanup active"
    else
      doctor_fail package.cache-maintenance "weekly package-cache cleanup is not active"
    fi
  fi

  if command -v eos-update >/dev/null 2>&1; then
    if [[ -f "$(packages_arch_eos_update_config_dest)" ]] &&
      cmp -s "$(packages_arch_eos_update_config_source)" "$(packages_arch_eos_update_config_dest)"; then
      doctor_pass package.eos-update "eos-update defaults to yay"
    else
      doctor_fail package.eos-update "eos-update yay default is not installed"
    fi
  fi

  if command -v dracut >/dev/null 2>&1; then
    if [[ -f "$(packages_arch_dracut_config_dest)" ]] &&
      cmp -s "$(packages_arch_dracut_config_source)" "$(packages_arch_dracut_config_dest)"; then
      doctor_pass package.dracut "local-NVMe initramfs policy installed"
    else
      doctor_fail package.dracut "local-NVMe initramfs policy is not installed"
    fi
  fi

  if packages_arch_is_huawei_mach_wx9; then
    if [[ -f "$(packages_arch_touchpad_config_dest)" ]] &&
      cmp -s "$(packages_arch_touchpad_config_source)" "$(packages_arch_touchpad_config_dest)"; then
      doctor_pass package.touchpad-config "Huawei touchpad preset installed"
    else
      doctor_fail package.touchpad-config "Huawei touchpad preset is not installed"
    fi

    if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]] && command -v xinput >/dev/null 2>&1; then
      if xinput list-props 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null |
        grep -Eq 'libinput Accel Profile Enabled \([0-9]+\):[[:space:]]+0, 0, 1' &&
        xinput list-props 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null |
        grep -Eq 'libinput Accel Custom Motion Points \([0-9]+\):[[:space:]]+0\.000000, 0\.042000, 0\.184013, 0\.276020' &&
        xinput list-props 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null |
        grep -Eq 'libinput Accel Custom Motion Step \([0-9]+\):[[:space:]]+0\.105000' &&
        xinput list-props 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null |
        grep -Eq 'libinput Natural Scrolling Enabled \([0-9]+\):[[:space:]]+1' &&
        xinput list-props 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null |
        grep -Eq 'libinput Click Method Enabled \([0-9]+\):[[:space:]]+0, 1'; then
        doctor_pass package.touchpad-runtime "smooth 0.4x-to-20x curve, natural scroll, and clickfinger active"
      else
        doctor_fail package.touchpad-runtime "Huawei touchpad runtime preset is not active"
      fi
    fi
  fi
}
