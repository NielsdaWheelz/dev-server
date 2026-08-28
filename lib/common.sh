#!/usr/bin/env bash

dev_server_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
dev_server_root="$(cd "$dev_server_lib_dir/.." && pwd)"
dev_server_home_dir="$HOME"
dev_server_assets_root="$dev_server_root/assets"

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

dev_server_sha256() {
  local path="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -- "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 -- "$path" | awk '{print $1}'
  else
    die "missing SHA-256 command: install sha256sum or shasum"
  fi
}

dev_server_sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | awk '{print $1}'
  else
    die "missing SHA-256 command: install sha256sum or shasum"
  fi
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
  printf '%s\n' "$dev_server_assets_root"
}

dev_server_home() {
  printf '%s\n' "$dev_server_home_dir"
}
