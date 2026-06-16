#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

packages_arch_pacman_file() {
  printf '%s/packages/arch.pacman.txt\n' "$dev_server_root"
}

packages_arch_aur_file() {
  printf '%s/packages/arch.aur.txt\n' "$dev_server_root"
}

packages_non_comment_lines() {
  sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' "$1"
}

packages_install() {
  local pacman_packages=()
  local aur_packages=()

  require_cmd pacman
  require_cmd sudo
  mapfile -t pacman_packages < <(packages_non_comment_lines "$(packages_arch_pacman_file)")
  if (( ${#pacman_packages[@]} > 0 )); then
    sudo pacman -Syu --needed "${pacman_packages[@]}"
  fi

  if [[ -s "$(packages_arch_aur_file)" ]]; then
    require_cmd paru
    mapfile -t aur_packages < <(packages_non_comment_lines "$(packages_arch_aur_file)")
    if (( ${#aur_packages[@]} > 0 )); then
      paru -S --needed "${aur_packages[@]}"
    fi
  fi
}

packages_doctor() {
  if command -v pacman >/dev/null 2>&1; then
    doctor_pass package.pacman "pacman present"
  else
    doctor_fail package.pacman "pacman missing"
  fi

  if [[ -s "$(packages_arch_aur_file)" ]]; then
    if command -v paru >/dev/null 2>&1; then
      doctor_pass package.paru "paru present"
    else
      doctor_fail package.paru "paru missing"
    fi
  fi
}
