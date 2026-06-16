#!/usr/bin/env bash

doctor_failures=0
doctor_warnings=0

doctor_reset() {
  doctor_failures=0
  doctor_warnings=0
}

doctor_pass() {
  printf 'pass  %-28s %s\n' "$1" "$2"
}

doctor_warn() {
  doctor_warnings=$((doctor_warnings + 1))
  printf 'warn  %-28s %s\n' "$1" "$2"
}

doctor_fail() {
  doctor_failures=$((doctor_failures + 1))
  printf 'fail  %-28s %s\n' "$1" "$2"
}

doctor_local_cmd() {
  local id="$1"
  local message="$2"
  local cmd="$3"
  local output

  if output="$(bash -o pipefail -lc "$cmd" 2>&1)"; then
    doctor_pass "$id" "${output:-$message}"
  else
    doctor_fail "$id" "${output:-failed: $message}"
  fi
}

doctor_threshold_cmd() {
  local id="$1"
  local message="$2"
  local cmd="$3"
  local output
  local rc

  set +e
  output="$(bash -o pipefail -lc "$cmd" 2>&1)"
  rc=$?
  set -e

  case "$rc" in
    0) doctor_pass "$id" "${output:-$message}" ;;
    2) doctor_warn "$id" "${output:-warning: $message}" ;;
    *) doctor_fail "$id" "${output:-failed: $message}" ;;
  esac
}

doctor_summary() {
  local label="${1:-doctor}"

  if (( doctor_failures > 0 )); then
    printf '%s: fail (%d failure(s), %d warning(s))\n' "$label" "$doctor_failures" "$doctor_warnings" >&2
    return 1
  fi

  if (( doctor_warnings > 0 )); then
    printf '%s: warn (%d warning(s))\n' "$label" "$doctor_warnings" >&2
    return 0
  fi

  printf '%s: pass\n' "$label"
}
