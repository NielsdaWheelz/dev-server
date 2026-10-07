#!/usr/bin/env bash

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

# The command is the installation interface; upstream owns its target layout.
# Reject scripts before execution so npm launchers and conflicts are not adopted.
ai_native_version() {
  local provider="$1" binary="$2" home output

  [[ -f "$binary" && -x "$binary" ]] || return 1
  python3 - "$binary" <<'PYTHON' || return 1
import sys

with open(sys.argv[1], "rb") as stream:
    magic = stream.read(4)
# ELF and the native Mach-O/fat headers, in either byte order.
if magic not in (b"\x7fELF", b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
                 b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
                 b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca",
                 b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"):
    raise SystemExit(1)
PYTHON
  home="$(dev_server_home)"
  case "$provider" in
  codex)
    output="$(HOME="$home" CODEX_HOME="$home/.codex" "$binary" --version)" || return 1
    [[ "$output" =~ ^codex-cli\ ([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?)$ ]] || return 1
    ;;
  claude)
    output="$(env -u CLAUDE_CONFIG_DIR HOME="$home" "$binary" --version)" || return 1
    [[ "$output" =~ ^([0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?)' (Claude Code)'$ ]] || return 1
    ;;
  *) return 1 ;;
  esac
  printf '%s\n' "${BASH_REMATCH[1]}"
}

ai_bootstrap_native() (
  set -euo pipefail

  local provider="$1" home installer url repair
  home="$(dev_server_home)"
  # Managed shells already own path order; keep installers from adding a block.
  export PATH="$home/bin:$home/.local/bin:$PATH"
  case "$provider" in
  codex)
    url=https://chatgpt.com/codex/install.sh
    repair="rerun $url with CODEX_HOME=$home/.codex and CODEX_INSTALL_DIR=$home/.local/bin"
    ;;
  claude)
    url=https://claude.ai/install.sh
    repair="rerun $url with HOME=$home and CLAUDE_CONFIG_DIR unset"
    ;;
  *) die "unknown native provider: $provider" ;;
  esac
  require_cmd bash
  require_cmd curl
  installer="$(mktemp "${TMPDIR:-/tmp}/dev-server-$provider-install.XXXXXX")" ||
    die "could not allocate a $provider installer candidate"
  trap 'rm -f -- "$installer"' EXIT
  dev_server_download "$url" "$installer" ||
    die "could not download the official $provider installer"
  [[ -s "$installer" ]] || die "empty $provider installer candidate"
  bash -n "$installer" || die "invalid $provider installer syntax"
  case "$provider" in
  codex)
    HOME="$home" CODEX_HOME="$home/.codex" CODEX_INSTALL_DIR="$home/.local/bin" \
      CODEX_NON_INTERACTIVE=1 bash "$installer" ||
      die "$provider native installation failed; partial state may remain; $repair"
    ;;
  claude)
    env -u CLAUDE_CONFIG_DIR HOME="$home" bash "$installer" ||
      die "$provider native installation failed; partial state may remain; $repair"
    ;;
  esac
)

ai_install_codex() {
  local home binary version
  home="$(dev_server_home)"
  binary="$home/.local/bin/codex"
  if [[ -e "$binary" || -L "$binary" ]]; then
    if ai_native_version codex "$binary" >/dev/null; then
      return 0
    fi
    render_result ACTION 'AI tool codex' "invalid native command at $binary; preserve the conflict and follow docs/gateway-separation-runbook.md#native-ai-maintenance; repair with https://chatgpt.com/codex/install.sh using CODEX_HOME=$home/.codex CODEX_INSTALL_DIR=$home/.local/bin"
    return 2
  fi
  ai_bootstrap_native codex || return $?
  version="$(ai_native_version codex "$binary")" ||
    die "codex native installation is invalid; partial state may remain; rerun https://chatgpt.com/codex/install.sh with CODEX_HOME=$home/.codex CODEX_INSTALL_DIR=$home/.local/bin"
  render_result INSTALLED 'AI tool' "codex@$version"
}

ai_install_claude() {
  local home binary version
  home="$(dev_server_home)"
  binary="$home/.local/bin/claude"
  if [[ -e "$binary" || -L "$binary" ]]; then
    if ai_native_version claude "$binary" >/dev/null; then
      return 0
    fi
    render_result ACTION 'AI tool claude' "invalid native command at $binary; preserve the conflict and follow docs/gateway-separation-runbook.md#native-ai-maintenance; repair with https://claude.ai/install.sh using HOME=$home and CLAUDE_CONFIG_DIR unset"
    return 2
  fi
  ai_bootstrap_native claude || return $?
  version="$(ai_native_version claude "$binary")" ||
    die "claude native installation is invalid; partial state may remain; rerun https://claude.ai/install.sh with HOME=$home and CLAUDE_CONFIG_DIR unset"
  render_result INSTALLED 'AI tool' "claude@$version"
}

ai_install_profiles() {
  local home
  local profile
  local codex_profile
  local command status=0

  home="$(dev_server_home)"
  profile="$(dev_server_assets_dir)/routers/ai-profile"
  [[ -f "$profile" && ! -L "$profile" ]] ||
    die "missing AI profile wrapper: $profile"

  codex_profile="$(mktemp "$home/bin/.codex-profile.XXXXXX")" || return 1
  if ! python3 - "$home" >"$codex_profile" <<'PY'
import shlex
import sys

home = sys.argv[1]
print('#!/usr/bin/env bash\ncase "${0##*/}" in')
print(f'  codex) [[ -n "${{CODEX_HOME:-}}" ]] || CODEX_HOME={shlex.quote(home + "/.codex")}; export CODEX_HOME ;;')
for command, account in (("codex-work", ".codex-work"),
                         ("codex-work2", ".codex-work2")):
    print(f'  {command}) export CODEX_HOME={shlex.quote(home + "/" + account)} ;;')
print('  *) exit 64 ;;\nesac')
print(f'exec {shlex.quote(home + "/.local/bin/codex")} "$@"')
PY
  then
    rm -f -- "$codex_profile"
    return 1
  fi
  for command in codex codex-work codex-work2; do
    if ! install_managed_file "$codex_profile" "$home/bin/$command" 0755 shell.config; then
      status=1
      break
    fi
  done
  rm -f -- "$codex_profile" || return 1
  ((status == 0)) || return 1
  install_managed_file "$profile" \
    "$home/bin/claude-work" 0755 shell.config || return 1
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

# Install the status line while preserving user settings and update policy.
# A missing or empty file starts from {}.
ai_claude_settings() {
  require_cmd python3
  python3 - "$1" "$2" "${3:-}" <<'PY'
import json
import os
import shlex
import stat
import sys

settings, script, publication = sys.argv[1:]

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
command = shlex.quote(script)
if publication == "--publish-skid-usage":
    command += " --publish-skid-usage"
value["statusLine"] = {"type": "command", "command": command}
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
    if ! ai_claude_settings "$settings" "$script" "${1:-}" >"$temporary"; then
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
  (($# == 0)) || [[ $# == 1 && $1 == --publish-skid-usage ]] ||
    die 'ai_install accepts only --publish-skid-usage'
  ai_validate_inputs
  ai_install_dirs || return 1
  ai_install_claude_settings "$@" || return 1
  ai_install_codex || return $?
  ai_install_claude || return $?
  ai_install_profiles || return 1
  ai_install_instructions || return 1
}
