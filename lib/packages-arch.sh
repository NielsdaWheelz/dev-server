#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

packages_arch_aur_packages=()
packages_arch_pacman_packages=()

packages_arch_version() {
  pacman -Q "$1" 2>/dev/null | awk 'NR == 1 { print $2 }'
}

packages_arch_snapshot() {
  LC_ALL=C pacman -Q | LC_ALL=C sort | dev_server_sha256_stream
}

packages_arch_process_identity() {
  local package="$1"
  local version="$2"

  [[ -n "$version" && "$version" != *$'\n'* ]] ||
    die "could not resolve installed $package version"
  printf '%s\0%s\n' "$package" "$version" | dev_server_sha256_stream
}

packages_arch_reconcile_tmux_activation() {
  local client_version server_version status

  client_version="$(tmux -V 2>/dev/null)" ||
    die "could not resolve installed tmux version"
  [[ "$client_version" =~ ^tmux[[:space:]][!-~]{1,60}$ ]] ||
    die "installed tmux version is invalid"
  if tmux list-sessions >/dev/null 2>&1; then
    server_version="$(tmux display-message -p '#{version}' 2>/dev/null)" || {
      render_result DEFERRED tmux \
        "running server version could not be observed; restart it manually"
      return 0
    }
    if [[ "$server_version" != "${client_version#tmux }" ]]; then
      render_result DEFERRED tmux \
        "running sessions keep the prior server until manually restarted"
    fi
    return 0
  else
    status=$?
  fi
  if ((status != 1)); then
    render_result DEFERRED tmux \
      "session state could not be proven idle; restart it manually"
    return 0
  fi
}

packages_arch_reconcile_docker_activation() {
  local version="$1"
  local containers desired_sha service_status

  desired_sha="$(packages_arch_process_identity docker "$version")"
  dev_server_active_sha_matches docker.package "$desired_sha" && return 0
  if systemctl is-active --quiet docker.service; then
    service_status=0
  else
    service_status=$?
  fi
  if ((service_status == 3)); then
    sudo systemctl start docker.service || die "could not start docker.service"
    systemctl is-active --quiet docker.service ||
      die "docker.service is not active after start"
    dev_server_record_active_sha docker.package "$desired_sha"
    render_result STARTED docker.config "updated daemon was inactive"
    return 0
  fi
  if ((service_status != 0)); then
    render_result DEFERRED docker \
      "updated daemon state could not be observed; restart it manually when safe"
    return 0
  fi
  if ! containers="$(
    docker --host unix:///var/run/docker.sock ps -q 2>/dev/null
  )"; then
    render_result DEFERRED docker \
      "updated daemon could not be proven idle; restart it manually when safe"
  elif [[ -n "$containers" ]]; then
    render_result DEFERRED docker \
      "updated daemon has running containers; restart it manually when safe"
  else
    sudo systemctl restart docker.service || die "could not restart docker.service"
    systemctl is-active --quiet docker.service ||
      die "docker.service is not active after restart"
    dev_server_record_active_sha docker.package "$desired_sha"
    render_result RESTARTED docker.config "updated daemon was idle"
  fi
}

packages_validate_inputs() {
  local aur_manifest="$dev_server_root/packages/arch.aur.txt"
  local aur_seen='|'
  local package
  local pacman_manifest="$dev_server_root/packages/arch.pacman.txt"
  local pacman_seen='|'
  local raw_line

  packages_arch_aur_packages=()
  packages_arch_pacman_packages=()
  [[ -f "$pacman_manifest" && ! -L "$pacman_manifest" ]] ||
    die "invalid package manifest: $pacman_manifest"
  [[ -f "$aur_manifest" && ! -L "$aur_manifest" ]] ||
    die "invalid package manifest: $aur_manifest"

  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    package="$(printf '%s\n' "${raw_line%%#*}" |
      sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "$package" ]] || continue
    [[ "$package" =~ ^[a-z0-9@._+:-]+$ ]] ||
      die "invalid package name in $pacman_manifest: $package"
    case "$pacman_seen" in
    *"|$package|"*) die "duplicate package in $pacman_manifest: $package" ;;
    esac
    packages_arch_pacman_packages+=("$package")
    pacman_seen+="$package|"
  done <"$pacman_manifest"
  while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
    package="$(printf '%s\n' "${raw_line%%#*}" |
      sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n "$package" ]] || continue
    [[ "$package" =~ ^[a-z0-9@._+:-]+$ ]] ||
      die "invalid package name in $aur_manifest: $package"
    case "$aur_seen" in
    *"|$package|"*) die "duplicate package in $aur_manifest: $package" ;;
    esac
    packages_arch_aur_packages+=("$package")
    aur_seen+="$package|"
  done <"$aur_manifest"

  if ((${#packages_arch_aur_packages[@]} > 0)) &&
    [[ "$pacman_seen" != *'|yay|'* ]] &&
    ! command -v yay >/dev/null 2>&1; then
    die "AUR packages require declared package helper yay"
  fi
}

packages_install() {
  local docker_after
  local -a pacman_arguments=(-Syu --needed)
  local packages_after
  local packages_before
  local tmux_after

  packages_validate_inputs
  require_cmd pacman
  require_cmd sort
  require_cmd sudo

  dev_server_validate_active_sha docker.package

  packages_before="$(packages_arch_snapshot)"

  if ((${#packages_arch_pacman_packages[@]} > 0)); then
    pacman_arguments+=("${packages_arch_pacman_packages[@]}")
  fi
  sudo pacman "${pacman_arguments[@]}"

  if ((${#packages_arch_aur_packages[@]} > 0)); then
    require_cmd yay
    yay -S --needed "${packages_arch_aur_packages[@]}"
  fi

  packages_after="$(packages_arch_snapshot)"
  if [[ "$packages_after" != "$packages_before" ]]; then
    render_result UPDATED "Arch packages"
  fi

  dev_server_prepare_active_dir
  tmux_after="$(packages_arch_version tmux || true)"
  [[ -n "$tmux_after" ]] || die "could not resolve installed tmux package version"
  packages_arch_reconcile_tmux_activation
  docker_after="$(packages_arch_version docker || true)"
  packages_arch_reconcile_docker_activation "$docker_after"
}
