#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${packages_macos_tailscale_app:=/Applications/Tailscale.app}"

packages_macos_snapshot() {
  {
    brew list --versions --formula
    brew list --versions --cask
  } | LC_ALL=C sort | dev_server_sha256_stream
}

packages_macos_tailscale_cli() {
  dev_server_app_store_tailscale_cli "$packages_macos_tailscale_app"
}

packages_validate_inputs() {
  local manifest="$dev_server_root/packages/Brewfile"

  [[ -f "$manifest" && ! -L "$manifest" ]] ||
    die "invalid package manifest: $manifest"
  (($(LC_ALL=C wc -c <"$manifest" | tr -d '[:space:]') <= 65536)) ||
    die "package manifest is too large: $manifest"
}

packages_install() {
  local upgrade="${1:-0}"
  local attempt
  local -a bundle_arguments=(--no-upgrade)
  local packages_after
  local packages_before

  packages_validate_inputs
  require_cmd brew
  require_cmd open
  require_cmd pgrep
  require_cmd sleep
  require_cmd sort
  packages_macos_tailscale_cli >/dev/null ||
    die "App Store Tailscale installation is unavailable"

  packages_before="$(packages_macos_snapshot)"
  if ((upgrade)); then
    brew update
    bundle_arguments=(--upgrade)
  fi
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle \
    "${bundle_arguments[@]}" --file "$dev_server_root/packages/Brewfile"
  packages_after="$(packages_macos_snapshot)"

  if [[ "$packages_after" != "$packages_before" ]]; then
    render_result UPDATED "Homebrew packages"
  fi

  if ! pgrep -x Tailscale >/dev/null 2>&1; then
    open -gj "$packages_macos_tailscale_app"
    for attempt in {1..20}; do
      pgrep -x Tailscale >/dev/null 2>&1 && break
      ((attempt < 20)) || die "Tailscale did not start"
      sleep 1
    done
    render_result STARTED Tailscale
  fi
}
