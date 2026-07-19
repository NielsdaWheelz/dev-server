#!/usr/bin/env bash

ai_tools() {
  printf 'codex claude opencode\n'
}

ai_routed_tools() {
  printf 'codex claude\n'
}

ai_direct_tools() {
  printf 'opencode\n'
}

ai_contexts() {
  printf 'personal work\n'
}

ai_tool_package() {
  case "$1" in
    codex) printf '@openai/codex\n' ;;
    claude) printf '@anthropic-ai/claude-code\n' ;;
    opencode) printf 'opencode-ai\n' ;;
    *) die "unknown AI tool: $1" ;;
  esac
}

ai_tool_install_method() {
  case "$1" in
    codex) printf 'npm\n' ;;
    claude) printf 'native\n' ;;
    opencode) printf 'npm\n' ;;
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

ai_opencode_config_source() {
  printf '%s/opencode/opencode.json\n' "$(dev_server_assets_dir)"
}

ai_opencode_config_dest() {
  printf '%s/.config/opencode/opencode.json\n' "$(dev_server_home)"
}

ai_opencode_managed_config_source() {
  printf '%s/opencode/managed.json\n' "$(dev_server_assets_dir)"
}

ai_render_opencode_config() {
  jq -s '.[0] * .[1]' "$(ai_opencode_config_source)" "$(ai_opencode_managed_config_source)"
}

ai_install_dirs() {
  local home
  local tool
  local context

  home="$(dev_server_home)"
  install -d -m 0755 "$home/bin" "$home/.local/bin" "$home/.local/libexec" "$home/.npm"
  install -d -m 0700 "$home/.config/opencode" "$home/.cache/opencode" \
    "$home/.local/share/opencode" "$home/.local/state/opencode"
  for tool in $(ai_routed_tools); do
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

  for tool in $(ai_routed_tools); do
    ln -sfn "$router_dest" "$home/bin/$tool"
    for context in $(ai_contexts); do
      shortcut="$home/bin/$tool-$context"
      ln -sfn "$router_dest" "$shortcut"
    done
  done
}

ai_install_direct_shortcuts() {
  local home
  local tool

  home="$(dev_server_home)"
  for tool in $(ai_direct_tools); do
    ln -sfn "$(ai_tool_real_binary "$tool")" "$home/bin/$tool"
  done
}

ai_install_opencode_config() {
  local source
  local managed_source
  local dest
  local rendered

  source="$(ai_opencode_config_source)"
  managed_source="$(ai_opencode_managed_config_source)"
  dest="$(ai_opencode_config_dest)"
  [[ -f "$source" ]] || die "missing OpenCode config asset: $source"
  [[ -f "$managed_source" ]] || die "missing managed OpenCode config asset: $managed_source"

  require_cmd jq
  jq empty "$source" >/dev/null || die "invalid OpenCode config JSON: $source"
  jq empty "$managed_source" >/dev/null || die "invalid managed OpenCode config JSON: $managed_source"
  rendered="$(mktemp "${TMPDIR:-/tmp}/dev-server-opencode.XXXXXX")"
  if ! ai_render_opencode_config > "$rendered"; then
    rm -f "$rendered"
    die "failed to render OpenCode config"
  fi
  install -d -m 0700 "$(dirname "$dest")"
  install -m 0600 "$rendered" "$dest"
  rm -f "$rendered"
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
  ai_install_direct_shortcuts
  ai_install_opencode_config
  ai_install_npm_globals
  ai_install_native
}

ai_doctor_direct_tool() {
  local tool="$1"
  local expected
  local home
  local shortcut
  local shortcut_target
  local version

  expected="$(ai_tool_real_binary "$tool")"
  home="$(dev_server_home)"
  shortcut="$home/bin/$tool"

  if [[ ! -x "$expected" ]]; then
    doctor_fail "ai.$tool" "missing managed binary: $expected"
    return
  fi
  if [[ ! -x "$shortcut" || ! -L "$shortcut" ]]; then
    doctor_fail "ai.$tool" "missing direct shortcut: $shortcut"
    return
  fi
  shortcut_target="$(readlink "$shortcut")"
  if [[ "$shortcut_target" != "$expected" ]]; then
    doctor_fail "ai.$tool" "$shortcut links to $shortcut_target, expected $expected"
    return
  fi

  version="$("$shortcut" --version)"
  doctor_pass "ai.$tool" "[$(ai_tool_install_method "$tool")] $version via $shortcut -> $expected"
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

  case "$tool" in
    opencode)
      ai_doctor_direct_tool "$tool"
      return
      ;;
  esac

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

ai_doctor_opencode() {
  local managed_source
  local dest
  local binary
  local models
  local auth
  local resolved_config
  local plan_agent
  local explore_agent
  local state_dir
  local state_mode

  managed_source="$(ai_opencode_managed_config_source)"
  dest="$(ai_opencode_config_dest)"
  binary="$(ai_tool_real_binary opencode)"

  if [[ ! -f "$dest" ]]; then
    doctor_fail ai.opencode.config "missing managed config: $dest"
  elif ! jq empty "$dest" >/dev/null 2>&1; then
    doctor_fail ai.opencode.config "invalid JSON: $dest"
  elif ! cmp -s <(ai_render_opencode_config) "$dest"; then
    doctor_fail ai.opencode.config "managed config differs from repo assets"
  else
    doctor_pass ai.opencode.config "Kimi K3 default and guarded permissions installed"
  fi

  if [[ "$(uname -s)" == "Linux" && ! -f /etc/arch-release ]]; then
    if [[ ! -f /etc/opencode/opencode.json ]]; then
      doctor_fail ai.opencode.managed "missing managed config: /etc/opencode/opencode.json"
    elif ! cmp -s "$managed_source" /etc/opencode/opencode.json; then
      doctor_fail ai.opencode.managed "managed config differs from $managed_source"
    else
      doctor_pass ai.opencode.managed "approval baseline installed at /etc/opencode/opencode.json"
    fi
  fi

  for state_dir in \
    "$(dev_server_home)/.config/opencode" \
    "$(dev_server_home)/.cache/opencode" \
    "$(dev_server_home)/.local/share/opencode" \
    "$(dev_server_home)/.local/state/opencode"; do
    if [[ ! -d "$state_dir" ]]; then
      doctor_fail ai.opencode.state "missing private state directory: $state_dir"
      return
    fi
    if state_mode="$(stat -c '%a' "$state_dir" 2>/dev/null)"; then
      :
    else
      state_mode="$(stat -f '%Lp' "$state_dir")"
    fi
    if [[ "$state_mode" != "700" ]]; then
      doctor_fail ai.opencode.state "$state_dir has mode $state_mode, expected 700"
      return
    fi
  done
  doctor_pass ai.opencode.state "config, cache, data, and state directories are private"

  if [[ ! -x "$binary" ]]; then
    return
  fi

  if resolved_config="$("$binary" debug config 2>&1)" &&
     jq -e '
       .model == "kimi-for-coding/k3" and
       .default_agent == "build" and
       .share == "disabled" and
       .server.hostname == "127.0.0.1" and
       .server.mdns == false and
       .provider["kimi-for-coding"].models.k3.limit.context == 262144 and
       .provider["kimi-for-coding"].models.k3.limit.output == 131072 and
       .agent.build.variant == "max" and
       .agent.plan.variant == "max" and
       .permission.bash == "ask" and
       .agent.build.permission.bash == "ask" and
       .agent.plan.permission.bash == "ask" and
       .agent.general.permission.bash == "ask" and
       .agent.explore.permission.bash == "ask" and
       .compaction.auto == true and
       .compaction.prune == false and
       .compaction.reserved == 10000
     ' >/dev/null <<< "$resolved_config"; then
    doctor_pass ai.opencode.runtime "K3/max/256K and managed runtime settings resolve correctly"
  else
    doctor_fail ai.opencode.runtime "effective OpenCode configuration is not the managed K3 baseline"
  fi

  if plan_agent="$("$binary" debug agent plan 2>&1)" &&
     explore_agent="$("$binary" debug agent explore 2>&1)" &&
     jq -e '
       ([.permission[] | select(
         .permission == "edit" and .pattern == "*" and .action == "deny"
       )] | length) > 0 and
       ([.permission[] | select(
         .permission == "task" and .pattern == "general" and .action == "deny"
       )] | length) > 0 and
       ([.permission[] | select(.permission == "bash")] | last | .action) == "ask"
     ' >/dev/null <<< "$plan_agent" &&
     jq -e '
       .tools.edit == false and
       .tools.write == false and
       ([.permission[] | select(.permission == "bash")] | last | .action) == "ask"
     ' >/dev/null <<< "$explore_agent"; then
    doctor_pass ai.opencode.agents "Plan and Explore retain guarded built-in semantics"
  else
    doctor_fail ai.opencode.agents "effective Plan or Explore permissions are unsafe"
  fi

  if models="$("$binary" models kimi-for-coding 2>&1)" &&
     printf '%s\n' "$models" | grep -Fqx 'kimi-for-coding/k3'; then
    doctor_pass ai.opencode.kimi "Kimi Code catalog exposes kimi-for-coding/k3"
  else
    doctor_fail ai.opencode.kimi "Kimi Code catalog does not expose kimi-for-coding/k3"
  fi

  if auth="$("$binary" auth list 2>&1)" &&
     printf '%s\n' "$auth" | grep -Eiq 'kimi-for-coding|Kimi For Coding'; then
    doctor_pass ai.opencode.auth "Kimi For Coding credential enrolled"
  else
    doctor_warn ai.opencode.auth "not enrolled; run: opencode auth login --provider kimi-for-coding"
  fi
}

ai_doctor() {
  local tool

  for tool in $(ai_tools); do
    ai_doctor_tool "$tool"
  done
  ai_doctor_opencode
}
