#!/usr/bin/env bash

ai_tools() {
  printf 'codex claude\n'
}

ai_contexts() {
  printf 'personal work\n'
}

ai_tool_package() {
  case "$1" in
    codex) printf '@openai/codex\n' ;;
    claude) printf '@anthropic-ai/claude-code\n' ;;
    *) die "unknown AI tool: $1" ;;
  esac
}

ai_tool_install_method() {
  case "$1" in
    codex) printf 'npm\n' ;;
    claude) printf 'native\n' ;;
    *) die "unknown AI tool: $1" ;;
  esac
}

ai_native_channel() {
  printf '%s\n' "${CLAUDE_NATIVE_CHANNEL:-stable}"
}

ai_tool_real_binary() {
  printf '%s/.local/bin/%s\n' "$(dev_server_home)" "$1"
}

ai_tool_home() {
  local tool="$1"
  local context="$2"

  case "$tool:$context" in
    codex:personal) printf '%s/.codex-personal\n' "$(dev_server_home)" ;;
    codex:work) printf '%s/.codex-work\n' "$(dev_server_home)" ;;
    claude:personal) printf '%s/.claude-personal\n' "$(dev_server_home)" ;;
    claude:work) printf '%s/.claude-work\n' "$(dev_server_home)" ;;
    *) die "unknown AI tool/context: $tool/$context" ;;
  esac
}

ai_router_source() {
  printf '%s/routers/ai-router\n' "$(dev_server_assets_dir)"
}

ai_router_dest() {
  printf '%s/.local/libexec/ai-router\n' "$(dev_server_home)"
}

ai_install_dirs() {
  local home
  local tool
  local context

  home="$(dev_server_home)"
  install -d -m 0755 "$home/bin" "$home/.local/bin" "$home/.local/libexec" "$home/.npm"
  for tool in $(ai_tools); do
    for context in $(ai_contexts); do
      install -d -m 0700 "$(ai_tool_home "$tool" "$context")"
    done
  done
}

ai_install_router() {
  local router_source
  local router_dest
  local home
  local tool
  local context
  local shortcut

  home="$(dev_server_home)"
  router_source="$(ai_router_source)"
  router_dest="$(ai_router_dest)"
  [[ -f "$router_source" ]] || die "missing AI router asset: $router_source"

  install -m 0755 "$router_source" "$router_dest"

  for tool in $(ai_tools); do
    ln -sfn "$router_dest" "$home/bin/$tool"
    for context in $(ai_contexts); do
      shortcut="$home/bin/$tool-$context"
      ln -sfn "$router_dest" "$shortcut"
    done
  done
}

ai_install_npm_globals() {
  local packages=()
  local tool

  for tool in $(ai_tools); do
    [[ "$(ai_tool_install_method "$tool")" == "npm" ]] || continue
    packages+=("$(ai_tool_package "$tool")")
  done

  if (( ${#packages[@]} == 0 )); then
    return 0
  fi

  require_cmd npm
  npm config set prefix "$(dev_server_home)/.local"
  npm install -g "${packages[@]}"

  if command -v corepack >/dev/null 2>&1; then
    corepack enable --install-directory "$(dev_server_home)/.local/bin"
  fi
}

ai_install_native_tool() {
  local tool="$1"
  local pkg

  case "$tool" in
    claude) ;;
    *) die "no native installer defined for AI tool: $tool" ;;
  esac

  require_cmd curl

  # Retire any npm-managed copy so the native launcher owns ~/.local/bin/<tool>.
  pkg="$(ai_tool_package "$tool")"
  if command -v npm >/dev/null 2>&1 && npm ls -g --depth=0 "$pkg" >/dev/null 2>&1; then
    log "removing npm-managed $tool ($pkg); native install supersedes it"
    npm uninstall -g "$pkg" >/dev/null 2>&1 || warn "failed to uninstall npm $pkg; continuing"
  fi

  log "installing native $tool ($(ai_native_channel))"
  curl -fsSL https://claude.ai/install.sh | bash -s -- "$(ai_native_channel)"
}

ai_install_native() {
  local tool

  for tool in $(ai_tools); do
    [[ "$(ai_tool_install_method "$tool")" == "native" ]] || continue
    ai_install_native_tool "$tool"
  done
}

ai_install() {
  ai_install_dirs
  ai_install_router
  ai_install_npm_globals
  ai_install_native
}

ai_doctor_tool() {
  local tool="$1"
  local expected
  local router
  local home
  local context
  local shortcut
  local shortcut_target
  local version

  expected="$(ai_tool_real_binary "$tool")"
  router="$(ai_router_dest)"
  home="$(dev_server_home)"

  if [[ ! -x "$expected" ]]; then
    doctor_fail "ai.$tool" "missing managed binary: $expected"
    return
  fi

  if [[ ! -x "$router" ]]; then
    doctor_fail "ai.$tool" "missing AI router: $router"
    return
  fi

  for shortcut in "$home/bin/$tool" "$home/bin/$tool-personal" "$home/bin/$tool-work"; do
    if [[ ! -x "$shortcut" ]]; then
      doctor_fail "ai.$tool" "missing shortcut: $shortcut"
      return
    fi
    if [[ ! -L "$shortcut" ]]; then
      doctor_fail "ai.$tool" "shortcut is not a symlink: $shortcut"
      return
    fi
    shortcut_target="$(readlink "$shortcut")"
    if [[ "$shortcut_target" != "$router" ]]; then
      doctor_fail "ai.$tool" "$shortcut links to $shortcut_target, expected $router"
      return
    fi
  done

  for context in $(ai_contexts); do
    if [[ ! -d "$(ai_tool_home "$tool" "$context")" ]]; then
      doctor_fail "ai.$tool" "missing state dir: $(ai_tool_home "$tool" "$context")"
      return
    fi
  done

  version="$("$home/bin/$tool" --version)"
  doctor_pass "ai.$tool" "[$(ai_tool_install_method "$tool")] $version via $router -> $expected"
}

ai_doctor() {
  local tool

  for tool in $(ai_tools); do
    ai_doctor_tool "$tool"
  done
}
