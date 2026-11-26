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

packages_arch_reconcile_docker_activation() {
  local version="$1"
  local attempt containers desired_sha service_status

  desired_sha="$(packages_arch_process_identity docker "$version")"
  dev_server_active_sha_matches docker.package "$desired_sha" && return 0
  if systemctl is-active --quiet docker.service; then
    service_status=0
  else
    service_status=$?
  fi
  if ((service_status == 3)); then
    if ! sudo systemctl start docker.service; then
      # On its first firewalld start Docker can create its zone, then exit
      # before the zone is usable. Give systemd's own restart time to finish.
      for ((attempt = 0; attempt < 10; attempt++)); do
        systemctl is-active --quiet docker.service && break
        sleep 1
      done
    fi
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
  local manifest path raw_line package
  local pacman_seen='|'
  local aur_seen='|'

  packages_arch_aur_packages=()
  packages_arch_pacman_packages=()
  # shellcheck disable=SC2154 # workstation selects and stages these paths.
  for manifest in "${workstation_manifests[@]}"; do
    path="$dev_server_root/$manifest"
    [[ -f "$path" && ! -L "$path" ]] || die "invalid package manifest: $path"
    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
      package="$(printf '%s\n' "${raw_line%%#*}" |
        sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
      [[ -n "$package" ]] || continue
      [[ "$package" =~ ^[a-z0-9@._+:-]+$ ]] || die "invalid package name in $manifest: $package"
      if [[ "$manifest" == *.aur.txt ]]; then
        [[ "$aur_seen" != *"|$package|"* ]] || die "duplicate package in $manifest: $package"
        packages_arch_aur_packages+=("$package")
        aur_seen+="$package|"
      else
        [[ "$pacman_seen" != *"|$package|"* ]] || die "duplicate package in $manifest: $package"
        packages_arch_pacman_packages+=("$package")
        pacman_seen+="$package|"
      fi
    done <"$path"
  done

  if ((${#packages_arch_aur_packages[@]} > 0)) &&
    [[ "$pacman_seen" != *'|yay|'* ]] &&
    ! command -v yay >/dev/null 2>&1; then
    die "AUR packages require declared package helper yay"
  fi
}

packages_install() {
  local docker_after
  local -a pacman_arguments=(-Syu --needed --noconfirm)
  local packages_after
  local packages_before

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
    yay -S --needed --noconfirm --sudoflags=--askpass \
      --answerclean None --answerdiff None --answeredit None \
      "${packages_arch_aur_packages[@]}"
  fi

  packages_after="$(packages_arch_snapshot)"
  if [[ "$packages_after" != "$packages_before" ]]; then
    render_result UPDATED "Arch packages"
  fi

  dev_server_prepare_active_dir
  docker_after="$(packages_arch_version docker || true)"
  # Both Linux workstations use Docker's firewalld zone from the first start.
  personal_arch_ensure_unit firewalld.service
  packages_arch_reconcile_docker_activation "$docker_after"
}
