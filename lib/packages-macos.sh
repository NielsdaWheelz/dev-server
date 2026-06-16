#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

packages_macos_file() {
  printf '%s/packages/Brewfile\n' "$dev_server_root"
}

packages_install() {
  require_cmd brew
  brew bundle --file "$(packages_macos_file)"
}

packages_doctor() {
  if command -v brew >/dev/null 2>&1; then
    doctor_pass package.brew "brew present"
    doctor_local_cmd package.bundle "Brewfile dependencies available" "HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file '$(packages_macos_file)'"
  else
    doctor_fail package.brew "brew missing"
  fi
}
