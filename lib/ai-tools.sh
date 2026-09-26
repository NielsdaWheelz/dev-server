#!/usr/bin/env bash

ai_require_codex_runtime() {
  local npm_version

  require_cmd node
  require_cmd npm
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' ||
    die "Codex requires Node.js 24 or newer"
  npm_version="$(npm --version)" || die "could not read the npm version"
  node - "$npm_version" <<'NODE' || die "Codex requires npm 11.17.0 or newer"
const actual = process.argv[2];
if (!/^\d+\.\d+\.\d+$/.test(actual)) process.exit(1);
const parts = actual.split('.').map(Number);
const minimum = [11, 17, 0];
for (let index = 0; index < minimum.length; index += 1) {
  if (parts[index] > minimum[index]) process.exit(0);
  if (parts[index] < minimum[index]) process.exit(1);
}
NODE
}

ai_validate_inputs() {
  local instructions
  local profile
  local statusline

  profile="$(dev_server_assets_dir)/routers/ai-profile"
  [[ -f "$profile" && ! -L "$profile" ]] ||
    die "invalid AI profile wrapper: $profile"
  instructions="$(dev_server_assets_dir)/agent-instructions.md"
  [[ -f "$instructions" && ! -L "$instructions" && -s "$instructions" ]] ||
    die "invalid shared AI instructions: $instructions"
  statusline="$(dev_server_assets_dir)/claude/statusline.sh"
  [[ -f "$statusline" && ! -L "$statusline" && -s "$statusline" ]] ||
    die "invalid claude status line script: $statusline"
  ai_codex_host validate || die 'invalid shared Codex declaration'
}

ai_codex_host() {
  python3 "$(dev_server_assets_dir)/codex/codex-shared.py" \
    --config "$(dev_server_assets_dir)/codex/profiles.json" \
    --host "${dev_server_ai_host:-devbox}" "$@"
}

ai_install_dirs() {
  local home account

  home="$(dev_server_home)"
  ensure_directory "$home/bin" 0755 || return 1
  ensure_directory "$home/.local" 0755 || return 1
  ensure_directory "$home/.local/bin" 0755 || return 1
  ensure_directory "$home/.local/share" 0755 || return 1
  for account in .codex .codex-work .codex-work2 .claude; do
    if [[ -d "$home/$account" && ! -L "$home/$account" ]]; then
      continue
    fi
    ensure_directory "$home/$account" 0700 || return 1
  done
  ensure_directory "$home/.claude-work" 0700 || return 1
}

ai_package_version() {
  local manifest="$1"
  local package="$2"

  node -e '
    const manifest = require(process.argv[1]);
    const packageName = process.argv[2];
    const version = manifest.version;
    if (manifest.name !== packageName || typeof version !== "string" || !/^\d+\.\d+\.\d+$/.test(version)) {
      process.exit(1);
    }
    process.stdout.write(version);
  ' "$manifest" "$package"
}

ai_codex_binary() {
  printf '%s/.local/bin/codex\n' "$(dev_server_home)"
}

ai_codex_manifest() {
  printf '%s/.local/lib/node_modules/@openai/codex/package.json\n' \
    "$(dev_server_home)"
}

ai_codex_matches() {
  local expected="$1"
  local binary
  local manifest
  local output

  binary="$(ai_codex_binary)"
  manifest="$(ai_codex_manifest)"
  [[ -x "$binary" && -f "$manifest" && ! -L "$manifest" ]] || return 1
  [[ "$(ai_package_version "$manifest" @openai/codex 2>/dev/null || true)" == "$expected" ]] || return 1
  output="$(CODEX_HOME="$(dev_server_home)/.codex-work" "$binary" --version)" ||
    return 1
  [[ "$output" == "codex-cli $expected" ]]
}

ai_install_codex() {
  local upgrade="${1:-0}"
  local binary
  local candidate
  local home
  local npm_prefix
  local prefix
  local status

  home="$(dev_server_home)"
  prefix="$home/.local"
  binary="$(ai_codex_binary)"
  npm_prefix="$(npm config get prefix)" || die "could not read the npm global prefix"
  if [[ "$npm_prefix" != "$prefix" ]]; then
    npm config set --location=user prefix "$prefix" ||
      die "could not configure the npm user-global prefix"
    [[ "$(npm config get prefix)" == "$prefix" ]] ||
      die "npm did not retain the user-global prefix"
    render_result CHANGED "npm global prefix" "$prefix"
  fi

  # codex 0.156 publishes its app-server socket as a symlink into a private
  # directory, which jarvis cannot reach; devbox holds the last release that binds
  # the declared path on both apply and upgrade (docs/issues/codex-daemon-socket.md).
  if [[ "${dev_server_ai_host:-devbox}" == devbox ]]; then
    candidate=0.155.1
  elif ((upgrade == 0)) && [[ -e "$binary" || -L "$binary" ]]; then
    if ! candidate="$(ai_package_version "$(ai_codex_manifest)" @openai/codex 2>/dev/null)" ||
      ! ai_codex_matches "$candidate"; then
      die 'installed Codex is invalid; run ./workstation upgrade or ./devbox upgrade to repair it'
    fi
    return 0
  else
    candidate="$(npm view @openai/codex dist-tags.latest)" ||
      die 'could not resolve the latest stable Codex release'
  fi
  [[ "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] ||
    die 'npm latest must identify a stable Codex release'
  if ai_codex_matches "$candidate"; then
    return 0
  fi
  if [[ -e "$(ai_codex_manifest)" || -L "$(ai_codex_manifest)" ||
  -e "$binary" || -L "$binary" ]]; then
    status=UPDATED
  else
    status=INSTALLED
  fi
  npm install --global --prefix "$prefix" --ignore-scripts \
    --no-audit --no-fund "@openai/codex@$candidate" || return 1
  ai_codex_matches "$candidate" ||
    die 'installed Codex does not match the selected version'
  render_result "$status" "AI tool" "codex@$candidate"
}

ai_claude_binary() {
  printf '%s/.local/bin/claude\n' "$(dev_server_home)"
}

ai_claude_version() {
  local binary="$1"
  local output

  output="$(HOME="$(dev_server_home)" "$binary" --version)" || return 1
  [[ "$output" =~ ^([0-9]+\.[0-9]+\.[0-9]+)' (Claude Code)'$ ]] || return 1
  printf '%s\n' "${BASH_REMATCH[1]}"
}

ai_claude_native_version() {
  local binary
  local expected_prefix
  local target
  local version

  binary="$(ai_claude_binary)"
  expected_prefix="$(dev_server_home)/.local/share/claude/versions/"
  [[ -L "$binary" ]] || return 1
  target="$(readlink "$binary")" || return 1
  [[ "$target" == "$expected_prefix"* && -f "$target" &&
    ! -L "$target" && -x "$target" ]] || return 1
  version="$(ai_claude_version "$binary")" || return 1
  [[ "$target" == "$expected_prefix$version" ]] || return 1
  printf '%s\n' "$version"
}

ai_bootstrap_claude_native() (
  set -euo pipefail

  local bytes
  local home
  local installer

  require_cmd bash
  require_cmd curl
  home="$(dev_server_home)"
  installer="$(mktemp "${TMPDIR:-/tmp}/dev-server-claude-install.XXXXXX")" ||
    die "could not allocate a Claude installer candidate"
  trap 'rm -f -- "$installer"' EXIT
  curl --proto '=https' --tlsv1.2 --fail --silent --show-error --location \
    --output "$installer" https://claude.ai/install.sh ||
    die "could not download the official Claude installer"
  [[ -f "$installer" && ! -L "$installer" ]] ||
    die "invalid Claude installer candidate"
  bytes="$(wc -c <"$installer" | tr -d ' ')"
  [[ "$bytes" =~ ^[0-9]+$ && "$bytes" -gt 0 && "$bytes" -le 1048576 ]] ||
    die "invalid Claude installer candidate size"
  bash -n "$installer" || die "invalid Claude installer syntax"
  HOME="$home" bash "$installer" latest ||
    die "Claude native installation failed"
)

ai_install_claude() {
  local upgrade="${1:-0}"
  local before
  local binary
  local home
  local status
  local version

  home="$(dev_server_home)"
  binary="$(ai_claude_binary)"
  if before="$(ai_claude_native_version)"; then
    ((upgrade)) || return 0
    HOME="$home" "$binary" install latest ||
      die "Claude native latest-channel reconciliation failed"
    version="$(ai_claude_native_version)" ||
      die "Claude native reconciliation produced an invalid installation"
    if [[ "$version" != "$before" ]]; then
      render_result UPDATED "AI tool" "claude@$version"
    fi
    return 0
  fi

  if [[ -e "$binary" || -L "$binary" ]]; then
    die "canonical Claude command is not an Anthropic native installation: $binary"
  fi
  if [[ -e "$home/.local/share/claude" || -L "$home/.local/share/claude" ]]; then
    status=UPDATED
  else
    status=INSTALLED
  fi
  ai_bootstrap_claude_native || return 1
  version="$(ai_claude_native_version)" ||
    die "Claude native installer produced an invalid installation"
  render_result "$status" "AI tool" "claude@$version"
}

ai_install_profiles() {
  local home
  local profile
  local command

  home="$(dev_server_home)"
  profile="$(dev_server_assets_dir)/routers/ai-profile"
  [[ -f "$profile" && ! -L "$profile" ]] ||
    die "missing AI profile wrapper: $profile"

  for command in codex codex-personal codex-work codex-work2 claude claude-personal claude-work; do
    install_managed_file "$profile" "$home/bin/$command" 0755 shell.config || return 1
  done
}

# Skid's marker is set only for new product-owned terminals. Bash login shells
# do not necessarily read .bashrc; install the same guarded source in the
# effective login file and in .bashrc for interactive subshells.
ai_install_skid_shell_init() {
  local home login path candidate mode
  home="$(dev_server_home)"
  login=''
  for path in .bash_profile .bash_login .profile; do
    if [[ -e "$home/$path" || -L "$home/$path" ]]; then
      login="$path"
      break
    fi
  done
  login="${login:-.bash_profile}"
  for path in "$login" .bashrc; do
    ai_install_skid_shell_source "$home/$path" || return $?
  done
  if [[ -e "$home/.zlogin" || -L "$home/.zlogin" ]]; then
    ai_install_skid_shell_source "$home/.zlogin" || return $?
  fi
}

ai_install_skid_shell_source() {
  local target="$1" candidate mode=0644
  [[ ! -L "$target" ]] || {
    render_result ACTION shell.config "skid shell startup target is a symlink: $target"
    return 2
  }
  if [[ -e "$target" ]]; then
    [[ -f "$target" ]] || return 1
    mode="$(file_mode "$target")" || return 1
  fi
  candidate="$(mktemp "$(dirname "$target")/.skid-shell-init.XXXXXX")" || return 1
  if ! python3 - "$target" >"$candidate" <<'PY'; then
import os
import sys

path = sys.argv[1]
begin = b"# dev-server skid shell init begin"
end = b"# dev-server skid shell init end"
block = (begin + b"\n"
         b'if [ "${SKIDBLADNIR_SHELL:-}" = 1 ]; then\n'
         b'  . "$HOME/.local/share/skidbladnir/current/providers/shell-init"\n'
         b'fi\n' + end + b"\n")
try:
    with open(path, "rb") as stream:
        old = stream.read(1048577)
except FileNotFoundError:
    old = b""
if len(old) > 1048576:
    raise SystemExit("shell startup file is too large")
if old.endswith(block):
    result = old
elif old.count(block) == 1 and old.count(begin) == 1 and old.count(end) == 1:
    offset = old.index(block)
    kept = old[:offset] + old[offset + len(block):]
    result = kept + (b"\n" if kept and not kept.endswith(b"\n") else b"") + block
elif begin in old or end in old:
    raise SystemExit("skid shell init marker is incomplete or duplicated")
else:
    result = old + (b"\n" if old and not old.endswith(b"\n") else b"") + block
sys.stdout.buffer.write(result)
PY
    rm -f -- "$candidate"
    return 1
  fi
  install_managed_file "$candidate" "$target" "$mode" shell.config || {
    rm -f -- "$candidate"
    return 1
  }
  rm -f -- "$candidate"
}

ai_install_instructions() {
  local instructions
  local instruction_home
  local relative

  instruction_home="$(dev_server_home)"
  instructions="$(dev_server_assets_dir)/agent-instructions.md"
  for relative in \
    .codex/AGENTS.md .codex-work/AGENTS.md .codex-work2/AGENTS.md \
    .claude/CLAUDE.md .claude-work/CLAUDE.md; do
    install_managed_file "$instructions" \
      "$instruction_home/$relative" 0600 ai.instructions || return 1
  done
}

# Both accounts share one binary and therefore one update policy: latest.
# Preserve unrelated settings; a missing or empty file starts from {}.
ai_claude_settings() {
  require_cmd python3
  python3 - "$1" "$2" <<'PY'
import json
import os
import stat
import sys

settings, script = sys.argv[1:]

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON key: {key}")
        value[key] = item
    return value

def reject_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")

try:
    metadata = os.lstat(settings)
except FileNotFoundError:
    value = {}
else:
    if not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(f"claude settings file is invalid: {settings}")
    if metadata.st_size > 1024 * 1024:
        raise SystemExit(f"claude settings file is too large: {settings}")
    if metadata.st_size:
        with open(settings, "r", encoding="utf-8") as stream:
            value = json.load(stream, object_pairs_hook=unique_object,
                              parse_constant=reject_constant)
    else:
        value = {}
if not isinstance(value, dict):
    raise SystemExit(f"claude settings must be an object: {settings}")
value["statusLine"] = {"type": "command", "command": script}
value["autoUpdatesChannel"] = "latest"
value.pop("minimumVersion", None)
json.dump(value, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY
}

ai_install_claude_settings() {
  local home script settings temporary account

  home="$(dev_server_home)"
  script="$home/bin/claude-statusline"
  install_managed_file "$(dev_server_assets_dir)/claude/statusline.sh" \
    "$script" 0755 claude.settings || return 1
  for account in .claude .claude-work; do
    settings="$home/$account/settings.json"
    temporary="$(mktemp "$home/$account/.settings.json.XXXXXX")" || return 1
    if ! ai_claude_settings "$settings" "$script" >"$temporary"; then
      rm -f -- "$temporary"
      return 1
    fi
    if ! install_managed_file "$temporary" "$settings" 0644 claude.settings; then
      rm -f -- "$temporary"
      return 1
    fi
    rm -f -- "$temporary" || return 1
  done
}

ai_install() {
  ai_require_codex_runtime
  ai_validate_inputs
  ai_install_dirs || return 1
  ai_install_claude_settings || return 1
  ai_install_codex "${1:-0}" || return 1
  ai_install_claude "${1:-0}" || return 1
  ai_install_profiles || return 1
  ai_install_skid_shell_init || return $?
  ai_install_instructions || return 1
}
