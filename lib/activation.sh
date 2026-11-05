#!/usr/bin/env bash

activation_check() {
  (($# == 1)) || return 64
  case "$1" in macos | arch | devbox) ;; *) return 64 ;; esac
  local helper
  helper="${dev_server_activation_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}/activation.py"
  python3 "$helper" check
}

activation_apply() {
  (($# == 2)) || return 64
  case "$1" in macos | arch | devbox) ;; *) return 64 ;; esac
  local library status
  library="${dev_server_activation_lib_dir:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
  if python3 "$library/activation.py" apply "$2" "$library"; then
    status=0
  else
    status=$?
  fi
  if ! dev_server_replay_results "$(dev_server_home)/.local/state/dev-server/apply.json" report; then
    render_result ACTION activation 'result unavailable; inspect ~/.local/state/dev-server/apply.json before retrying'
    return 2
  fi
  case "$status" in
  0 | 1) return "$status" ;;
  *)
    render_result ACTION activation 'completion requires attention; inspect ~/.local/state/dev-server/apply.json before retrying'
    return 2
    ;;
  esac
}

if [[ "${1:-}" == --worker ]]; then
  (($# == 2)) || exit 64
  set -euo pipefail
  activation_library="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=lib/common.sh
  source "$activation_library/common.sh"
  # shellcheck source=lib/ai-tools.sh
  source "$activation_library/ai-tools.sh"
  dev_server_home_dir="$HOME"
  dev_server_result_jsonl="$2/results.jsonl"
  dev_server_acquire_lock "$HOME/.local/state/dev-server/activation.lock" 9 activation
  ai_maintain_codex_daemons
fi
