#!/usr/bin/env bash

dev_server_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dev_server_root="$(cd "$dev_server_lib_dir/.." && pwd)"

log() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

is_truthy() {
  case "${1:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

canonical_path() {
  local target="$1"
  local dir
  local base

  if command -v realpath >/dev/null 2>&1; then
    realpath "$target" 2>/dev/null && return
  fi

  dir="$(dirname "$target")"
  base="$(basename "$target")"
  if [[ -d "$dir" ]]; then
    (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
  else
    printf '%s\n' "$target"
  fi
}

resolve_path() {
  local target="${1:-$PWD}"
  local dir
  local base

  if [[ "$target" != /* ]]; then
    target="$PWD/$target"
  fi

  if [[ -d "$target" ]]; then
    (cd "$target" && pwd -P)
    return
  fi

  dir="$(dirname "$target")"
  base="$(basename "$target")"
  if [[ -d "$dir" ]]; then
    (cd "$dir" && printf '%s/%s\n' "$(pwd -P)" "$base")
  else
    printf '%s\n' "$target"
  fi
}

dev_server_assets_dir() {
  printf '%s\n' "${DEV_SERVER_ASSETS_DIR:-$dev_server_root/assets}"
}

dev_server_home() {
  printf '%s\n' "${DEV_SERVER_HOME:-$HOME}"
}
