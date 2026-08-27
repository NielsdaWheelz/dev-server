#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

packages_macos_file() {
  printf '%s/packages/Brewfile\n' "$dev_server_root"
}

packages_macos_tailscale_cli() {
  if command -v tailscale >/dev/null 2>&1; then
    command -v tailscale
  elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
    printf '/Applications/Tailscale.app/Contents/MacOS/Tailscale\n'
  else
    return 1
  fi
}

packages_macos_configure_tailscale() {
  if [[ ! -d /Applications/Tailscale.app ]]; then
    brew install --cask tailscale-app
  fi
  open -gj -a Tailscale
}

packages_macos_pin_tmux_if_exact() {
  local config="$dev_server_root/assets/skidbladnir/host-config-macbook.json"
  local tmux_path
  local tmux_version
  tmux_path="$(jq -er '.tmux.path' "$config")" || die "MacBook tmux path is invalid"
  tmux_version="$(jq -er '.tmux.version' "$config")" || die "MacBook tmux version is invalid"

  if [[ -x "$tmux_path" && "$($tmux_path -V 2>/dev/null || true)" == "$tmux_version" ]] &&
    ! packages_macos_tmux_is_pinned; then
    brew pin --formula tmux
  fi
}

packages_macos_tmux_is_pinned() {
  brew list --pinned --formula 2>/dev/null | grep -Fxq tmux
}

packages_macos_doctor_tmux_pin() {
  if packages_macos_tmux_is_pinned; then
    doctor_pass package.tmux-pin "Homebrew tmux formula protected from unreviewed upgrades"
  else
    doctor_fail package.tmux-pin "Homebrew tmux formula is not pinned; run ./workstation converge"
  fi
}

packages_install() {
  require_cmd brew
  packages_macos_pin_tmux_if_exact
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle --file "$(packages_macos_file)"
  packages_macos_pin_tmux_if_exact
  packages_macos_configure_tailscale
}

packages_doctor() {
  if command -v brew >/dev/null 2>&1; then
    doctor_pass package.brew "brew present"
    doctor_local_cmd package.bundle "Brewfile dependencies available" "HOMEBREW_NO_AUTO_UPDATE=1 brew bundle check --file '$(packages_macos_file)'"
    packages_macos_doctor_tmux_pin
  else
    doctor_fail package.brew "brew missing"
  fi

  if [[ -d /Applications/Tailscale.app ]]; then
    doctor_pass package.tailscale-app "Tailscale app installed"
  else
    doctor_fail package.tailscale-app "Tailscale app missing"
  fi

  if command -v zsh >/dev/null 2>&1 && zsh -c 'command -v mosh-server' >/dev/null 2>&1; then
    doctor_pass package.mosh-server "Mosh server available to noninteractive SSH shells"
  else
    doctor_fail package.mosh-server "Mosh server missing from the noninteractive zsh PATH"
  fi

  local tailscale_cli
  if tailscale_cli="$(packages_macos_tailscale_cli)" &&
    TAILSCALE_BE_CLI=1 "$tailscale_cli" status --json 2>/dev/null |
    jq -e '.BackendState == "Running"' >/dev/null; then
    doctor_pass package.tailscale-session "Tailscale connected to a tailnet"
  else
    doctor_fail package.tailscale-session "Tailscale is not connected; open the app and sign in"
  fi
}
