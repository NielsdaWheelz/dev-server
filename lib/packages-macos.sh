#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
: "${packages_macos_tailscale_app:=/Applications/Tailscale.app}"

packages_macos_tmux_version() {
  command -v tmux >/dev/null 2>&1 || return 0
  tmux -V 2>/dev/null || true
}

packages_macos_snapshot() {
  {
    brew list --versions --formula
    brew list --versions --cask
  } | LC_ALL=C sort | dev_server_sha256_stream
}

packages_macos_tailscale_cli() {
  local cli="$packages_macos_tailscale_app/Contents/MacOS/Tailscale"
  local receipt="$packages_macos_tailscale_app/Contents/_MASReceipt/receipt"

  [[ -d "$packages_macos_tailscale_app" &&
    ! -L "$packages_macos_tailscale_app" &&
    -f "$cli" && ! -L "$cli" && -x "$cli" &&
    -f "$receipt" && ! -L "$receipt" ]] || return 1
  printf '%s\n' "$cli"
}

packages_macos_reconcile_tmux_activation() {
  local client_version="$1"
  local server_version status

  dev_server_tmux_version_is_valid "$client_version" ||
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

packages_validate_inputs() {
  local manifest="$dev_server_root/packages/Brewfile"

  [[ -f "$manifest" && ! -L "$manifest" ]] ||
    die "invalid package manifest: $manifest"
  (($(LC_ALL=C wc -c <"$manifest" | tr -d '[:space:]') <= 65536)) ||
    die "package manifest is too large: $manifest"
}

packages_install() {
  local attempt
  local tmux_after
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
  brew update
  HOMEBREW_NO_AUTO_UPDATE=1 brew bundle \
    --file "$dev_server_root/packages/Brewfile"
  tmux_after="$(packages_macos_tmux_version)"
  packages_after="$(packages_macos_snapshot)"

  if [[ "$packages_after" != "$packages_before" ]]; then
    render_result UPDATED "Homebrew packages"
  fi

  packages_macos_reconcile_tmux_activation "$tmux_after"

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
