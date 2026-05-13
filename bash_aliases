alias ll='ls -lah'
alias gs='git status --short --branch'
alias t='tmux new -A -s main'
alias work='cd ~/src/work'
alias personal='cd ~/src/personal'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'

# Route Codex auth/state by workspace. Keep ChatGPT credentials isolated per CODEX_HOME.
export CODEX_HOME_PERSONAL="$HOME/.codex-personal"
export CODEX_HOME_WORK="$HOME/.codex-work"

_codex_abspath() {
  local target="${1:-$PWD}"

  if [[ "$target" = /* ]]; then
    if [[ -d "$target" ]]; then
      (cd "$target" && pwd -P)
    else
      printf '%s\n' "$target"
    fi
  else
    if [[ -d "$PWD/$target" ]]; then
      (cd "$PWD/$target" && pwd -P)
    else
      printf '%s/%s\n' "$PWD" "$target"
    fi
  fi
}

_codex_home_for_args() {
  local target="$PWD"
  local arg
  local next_is_cd=0

  for arg in "$@"; do
    if (( next_is_cd )); then
      target="$arg"
      next_is_cd=0
      continue
    fi

    case "$arg" in
      -C|--cd)
        next_is_cd=1
        ;;
      --cd=*)
        target="${arg#--cd=}"
        ;;
    esac
  done

  local dir
  dir="$(_codex_abspath "$target")"

  case "$dir/" in
    "$HOME"/src/work/*)
      printf '%s\n' "$CODEX_HOME_WORK"
      ;;
    *)
      printf '%s\n' "$CODEX_HOME_PERSONAL"
      ;;
  esac
}

codex() {
  local real_codex="/usr/bin/codex"

  if [[ -n "${CODEX_HOME:-}" ]]; then
    "$real_codex" "$@"
  else
    CODEX_HOME="$(_codex_home_for_args "$@")" "$real_codex" "$@"
  fi
}

codex-home() {
  _codex_home_for_args "$@"
}

codex-personal() {
  CODEX_HOME="$CODEX_HOME_PERSONAL" codex "$@"
}

codex-work() {
  CODEX_HOME="$CODEX_HOME_WORK" codex "$@"
}
