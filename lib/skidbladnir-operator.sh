#!/usr/bin/env bash

skidbladnir_operator_require_macbook() {
  [[ "$(uname -s)" == Darwin ]] || die "./skidbladnir is the MacBook-only fixed-fleet operator"
}

skidbladnir_operator_ssh_bash() {
  local host="$1"
  local script="$2"
  ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 \
    "$host" bash -o pipefail -s <<<"$script"
}

skidbladnir_operator_require_remote_release_pin() {
  local target="$1"
  local host command local_digest remote_digest
  # shellcheck disable=SC2154 # Defined by lib/skidbladnir.sh before this library is sourced.
  if [[ ! -f "$skidbladnir_release_pin_file" || -L "$skidbladnir_release_pin_file" ]]; then
    printf '%s\n' 'error: local Skidbladnir release pin is not a regular file' >&2
    return 1
  fi
  if ! skidbladnir_release_values macos >/dev/null 2>&1; then
    printf '%s\n' 'error: local Skidbladnir release pin is pending or invalid' >&2
    return 1
  fi
  local_digest="$(skidbladnir_sha256 "$skidbladnir_release_pin_file")"
  case "$target" in
  DevServer)
    host=dev-server
    command='set -euo pipefail
source "$HOME/.local/share/dev-server/lib/common.sh"
source "$HOME/.local/share/dev-server/lib/skidbladnir.sh"
skidbladnir_sha256 "$skidbladnir_release_pin_file"'
    ;;
  Arch)
    host=arch
    command='set -euo pipefail
repo="$HOME/src/personal/dev-server"
source "$repo/lib/common.sh"
source "$repo/lib/skidbladnir.sh"
skidbladnir_sha256 "$skidbladnir_release_pin_file"'
    ;;
  *) die "unsupported release pin target: $target" ;;
  esac
  if ! remote_digest="$(skidbladnir_operator_ssh_bash "$host" "$command")"; then
    printf 'error: could not read the %s release pin digest\n' "$target" >&2
    return 1
  fi
  if [[ ! "$local_digest" =~ ^[0-9a-f]{64}$ || ! "$remote_digest" =~ ^[0-9a-f]{64}$ ||
    "$remote_digest" != "$local_digest" ]]; then
    printf 'error: %s release pin differs from the MacBook source pin; converge that host before continuing\n' "$target" >&2
    return 1
  fi
}

skidbladnir_operator_doctor_local() {
  doctor_reset
  skidbladnir_doctor macos
  doctor_summary "MacBook Skidbladnir"
}

skidbladnir_operator_doctor_remote() {
  local target="$1"
  local host command
  skidbladnir_operator_require_remote_release_pin "$target" || return
  case "$target" in
  DevServer)
    host=dev-server
    command='set -euo pipefail
source "$HOME/.local/share/dev-server/lib/common.sh"
source "$HOME/.local/share/dev-server/lib/doctor.sh"
source "$HOME/.local/share/dev-server/lib/skidbladnir.sh"
doctor_reset
skidbladnir_doctor devbox
doctor_summary "Devbox Skidbladnir"'
    ;;
  Arch)
    host=arch
    command='set -euo pipefail
repo="$HOME/src/personal/dev-server"
source "$repo/lib/common.sh"
source "$repo/lib/doctor.sh"
source "$repo/lib/skidbladnir.sh"
doctor_reset
skidbladnir_doctor arch
doctor_summary "Arch Skidbladnir"'
    ;;
  *) die "unsupported fleet doctor target: $target" ;;
  esac
  skidbladnir_operator_ssh_bash "$host" "$command"
}

skidbladnir_operator_doctor() {
  local failures=0
  printf '%s\n' '==> MacBook gateway'
  if ! skidbladnir_operator_doctor_local; then
    failures=$((failures + 1))
  fi
  printf '%s\n' '==> Devbox gateway'
  if ! skidbladnir_operator_doctor_remote DevServer; then
    failures=$((failures + 1))
  fi
  printf '%s\n' '==> Arch gateway'
  if ! skidbladnir_operator_doctor_remote Arch; then
    failures=$((failures + 1))
  fi

  if ((failures > 0)); then
    printf 'Fleet gateway doctor: fail (%d host%s).\n' \
      "$failures" "$([[ "$failures" == 1 ]] || printf s)" >&2
    return 1
  fi
  printf '%s\n' 'Fleet gateway doctor: pass.'
}

skidbladnir_operator_invite() {
  local manifest="$1"
  local local_binary="$2"
  skidbladnir_operator_doctor >/dev/null || return
  skidbladnir_invite "$manifest" "$local_binary"
}

skidbladnir_operator_reconciled_lifetime_call() {
  local target="$1"
  local command
  case "$target" in
  Local)
    skidbladnir_reconciled_lifetime_digest_local
    ;;
  DevServer)
    skidbladnir_operator_require_remote_release_pin DevServer || return
    command='set -euo pipefail
source "$HOME/.local/share/dev-server/lib/common.sh"
source "$HOME/.local/share/dev-server/lib/skidbladnir.sh"
skidbladnir_reconciled_lifetime_digest_local'
    skidbladnir_operator_ssh_bash dev-server "$command"
    ;;
  Arch)
    skidbladnir_operator_require_remote_release_pin Arch || return
    command='set -euo pipefail
repo="$HOME/src/personal/dev-server"
source "$repo/lib/common.sh"
source "$repo/lib/skidbladnir.sh"
skidbladnir_reconciled_lifetime_digest_local'
    skidbladnir_operator_ssh_bash arch "$command"
    ;;
  *) die "unsupported lifetime digest target: $target" ;;
  esac
}

skidbladnir_operator_reconciled_lifetime_capture() {
  local target="$1"
  local status
  set +e
  skidbladnir_operator_reconciled_lifetime_call "$target"
  status=$?
  printf 'skidbladnir-reconciled-lifetime-status:%d\n' "$status"
}

skidbladnir_operator_reconciled_lifetime_digests() (
  set +x
  local local_result="" devbox_result="" arch_result=""
  local local_completion="" devbox_completion="" arch_completion=""
  local local_extra="" devbox_extra="" arch_extra=""
  local local_status=0 devbox_status=0 arch_status=0

  exec 3< <(skidbladnir_operator_reconciled_lifetime_capture Local 2>/dev/null)
  exec 4< <(skidbladnir_operator_reconciled_lifetime_capture DevServer 2>/dev/null)
  exec 5< <(skidbladnir_operator_reconciled_lifetime_capture Arch 2>/dev/null)
  IFS= read -r local_result <&3 || local_status=65
  IFS= read -r devbox_result <&4 || devbox_status=65
  IFS= read -r arch_result <&5 || arch_status=65
  IFS= read -r local_completion <&3 || local_status=65
  IFS= read -r devbox_completion <&4 || devbox_status=65
  IFS= read -r arch_completion <&5 || arch_status=65
  if IFS= read -r local_extra <&3 || [[ -n "$local_extra" ]]; then local_status=65; fi
  if IFS= read -r devbox_extra <&4 || [[ -n "$devbox_extra" ]]; then devbox_status=65; fi
  if IFS= read -r arch_extra <&5 || [[ -n "$arch_extra" ]]; then arch_status=65; fi
  exec 3<&- 4<&- 5<&-
  if ((local_status == 0)) && [[ "$local_completion" =~ ^skidbladnir-reconciled-lifetime-status:([0-9]+)$ ]]; then
    local_status="${BASH_REMATCH[1]}"
  else
    local_status=65
  fi
  if ((devbox_status == 0)) && [[ "$devbox_completion" =~ ^skidbladnir-reconciled-lifetime-status:([0-9]+)$ ]]; then
    devbox_status="${BASH_REMATCH[1]}"
  else
    devbox_status=65
  fi
  if ((arch_status == 0)) && [[ "$arch_completion" =~ ^skidbladnir-reconciled-lifetime-status:([0-9]+)$ ]]; then
    arch_status="${BASH_REMATCH[1]}"
  else
    arch_status=65
  fi

  if ((local_status != 0 || devbox_status != 0 || arch_status != 0)) ||
    [[ ! "$local_result" =~ ^[0-9a-f]{64}$ ]] ||
    [[ ! "$devbox_result" =~ ^[0-9a-f]{64}$ ]] ||
    [[ ! "$arch_result" =~ ^[0-9a-f]{64}$ ]]; then
    die "Couldn't reconcile and read the whole fleet lifetime. Nothing was displayed. Run ./skidbladnir doctor."
  fi

  printf 'Local %s\nDevServer %s\nArch %s\n' "$local_result" "$devbox_result" "$arch_result"
)

skidbladnir_operator_accept_host() {
  local target="${1:-}"
  local converge_gate="${2:-}"
  local reconciliation_gate="${3:-}"
  local command
  if [[ "$converge_gate" != --allow-host-convergence ||
    "$reconciliation_gate" != --allow-inventory-reconciliation ||
    "${SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE:-}" != host-acceptance-v1 ]]; then
    printf 'NOT_RUN  skidbladnir.accept-host        exact convergence and inventory-reconciliation authorization is required; no host was touched\n' >&2
    printf 'Usage: ./skidbladnir accept-host <Local|DevServer|Arch> --allow-host-convergence --allow-inventory-reconciliation\n' >&2
    return 64
  fi
  case "$target" in
  Local)
    skidbladnir_accept_host_local macos Local
    ;;
  DevServer)
    skidbladnir_operator_require_remote_release_pin DevServer || return
    command='set -euo pipefail
source "$HOME/.local/share/dev-server/lib/common.sh"
source "$HOME/.local/share/dev-server/lib/doctor.sh"
source "$HOME/.local/share/dev-server/lib/skidbladnir.sh"
SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE=host-acceptance-v1 skidbladnir_accept_host_local devbox DevServer'
    skidbladnir_operator_ssh_bash dev-server "$command"
    ;;
  Arch)
    skidbladnir_operator_require_remote_release_pin Arch || return
    command='set -euo pipefail
repo="$HOME/src/personal/dev-server"
source "$repo/lib/common.sh"
source "$repo/lib/doctor.sh"
source "$repo/lib/skidbladnir.sh"
SKIDBLADNIR_ALLOW_HOST_ACCEPTANCE=host-acceptance-v1 skidbladnir_accept_host_local arch Arch'
    skidbladnir_operator_ssh_bash arch "$command"
    ;;
  *) die "unsupported fleet acceptance target: $target" ;;
  esac
}

skidbladnir_operator_reboot_acceptance() {
  local phase="${1:-}"
  local target="${2:-}"
  local gate="${3:-}"
  local command
  if [[ "$gate" != --allow-reboot-acceptance ||
    "${SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE:-}" != reboot-acceptance-v1 ]]; then
    printf 'NOT_RUN  skidbladnir.accept-host.reboot exact reboot acceptance authorization is required; no checkpoint was changed\n' >&2
    printf 'Usage: ./skidbladnir <prepare-reboot|verify-reboot> <Local|DevServer|Arch> --allow-reboot-acceptance\n' >&2
    return 64
  fi
  case "$phase" in
  prepare) ;;
  verify) ;;
  *) die "unsupported reboot acceptance phase: $phase" ;;
  esac
  case "$target" in
  Local)
    "skidbladnir_${phase}_reboot_local" macos Local
    ;;
  DevServer)
    skidbladnir_operator_require_remote_release_pin DevServer || return
    if [[ "$phase" == prepare ]]; then
      command='set -euo pipefail
source "$HOME/.local/share/dev-server/lib/common.sh"
source "$HOME/.local/share/dev-server/lib/doctor.sh"
source "$HOME/.local/share/dev-server/lib/skidbladnir.sh"
SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1 skidbladnir_prepare_reboot_local devbox DevServer'
    else
      command='set -euo pipefail
source "$HOME/.local/share/dev-server/lib/common.sh"
source "$HOME/.local/share/dev-server/lib/doctor.sh"
source "$HOME/.local/share/dev-server/lib/skidbladnir.sh"
SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1 skidbladnir_verify_reboot_local devbox DevServer'
    fi
    skidbladnir_operator_ssh_bash dev-server "$command"
    ;;
  Arch)
    skidbladnir_operator_require_remote_release_pin Arch || return
    if [[ "$phase" == prepare ]]; then
      command='set -euo pipefail
repo="$HOME/src/personal/dev-server"
source "$repo/lib/common.sh"
source "$repo/lib/doctor.sh"
source "$repo/lib/skidbladnir.sh"
SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1 skidbladnir_prepare_reboot_local arch Arch'
    else
      command='set -euo pipefail
repo="$HOME/src/personal/dev-server"
source "$repo/lib/common.sh"
source "$repo/lib/doctor.sh"
source "$repo/lib/skidbladnir.sh"
SKIDBLADNIR_ALLOW_REBOOT_ACCEPTANCE=reboot-acceptance-v1 skidbladnir_verify_reboot_local arch Arch'
    fi
    skidbladnir_operator_ssh_bash arch "$command"
    ;;
  *) die "unsupported fleet reboot acceptance target: $target" ;;
  esac
}

skidbladnir_operator_service() {
  local action="$1"
  local target="$2"
  local verb
  case "$action" in
  outage) verb=stop ;;
  recover) verb=start ;;
  *) die "unsupported gateway action: $action" ;;
  esac

  case "$target" in
  Local)
    if [[ "$action" == outage ]]; then
      launchctl bootout "gui/$(id -u)/dev.niels.skidbladnir"
    else
      launchctl bootstrap "gui/$(id -u)" \
        /Users/nnandal/Library/LaunchAgents/dev.niels.skidbladnir.plist
    fi
    ;;
  DevServer)
    ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 \
      dev-server "systemctl --user $verb skidbladnir.service"
    ;;
  Arch)
    ssh -T -o BatchMode=yes -o RequestTTY=no -o ConnectTimeout=10 -o ConnectionAttempts=1 \
      arch "systemctl --user $verb skidbladnir.service"
    ;;
  *) die "unsupported fleet command target: $target" ;;
  esac

  if [[ "$action" == outage ]]; then
    printf 'Gateway outage active on %s. tmux and Tailscale Serve were not touched.\n' "$target"
  else
    printf 'Gateway recovered on %s. tmux and Tailscale Serve were not touched.\n' "$target"
  fi
}
