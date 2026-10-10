#!/usr/bin/env bash

if ! declare -F ai_native_version >/dev/null; then
  # shellcheck source=lib/ai-tools.sh
  source "$(dirname "${BASH_SOURCE[0]}")/ai-tools.sh"
fi

# Keep canonical commands so upstream upgrades reach every future launch.
skidbladnir_native_paths() {
  local home="$1" codex claude
  codex="$home/.local/bin/codex"
  claude="$home/.local/bin/claude"
  ai_native_version codex "$codex" >/dev/null || return 1
  ai_native_version claude "$claude" >/dev/null || return 1
  printf '%s\t%s\t%s\n' "$codex" "$claude" "$home"
}

skidbladnir_native_pin() {
  local pin
  pin="$(dev_server_assets_dir)/skid-provider/native-control.json"
  dev_server_strict_json_file "$pin" 4096 || return 1
  python3 - "$pin" <<'PIN'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
if not isinstance(value, dict) or value.keys() != {"repository", "entryPoint", "installedCommand"}:
    raise SystemExit(1)
if not isinstance(value["repository"], str) or not re.fullmatch(r"https://[a-zA-Z0-9./_-]+\.git", value["repository"]):
    raise SystemExit(1)
if value["entryPoint"] != "provider-runtime-control" or value["installedCommand"] != "skidbladnir-provider-runtime-control":
    raise SystemExit(1)
print("\t".join(value[key] for key in ("repository", "entryPoint", "installedCommand")))
PIN
}

skidbladnir_provider_preflight() {
  local home="$1" source
  skidbladnir_native_pin >/dev/null || die 'invalid skid native-control declaration'
  if ! skidbladnir_native_paths "$home" >/dev/null; then
    render_result ACTION skid.providers 'install the shared native codex and claude before skid'
    return 2
  fi
  if ! command -v git >/dev/null || ! command -v python3 >/dev/null; then
    render_result ACTION skid.native 'git and python3 are required for the native helper'
    return 2
  fi
  skidbladnir_shell_setup "$home" check || return $?
  for source in native-control-launch native-control-claude provider-command shell-init terminal-context-init \
    claude-agent-identity/.claude-plugin/plugin.json \
    claude-agent-identity/hooks/hooks.json claude-agent-identity/bin/agent-hook; do
    [[ -f "$(dev_server_assets_dir)/skid-provider/$source" &&
       ! -L "$(dev_server_assets_dir)/skid-provider/$source" ]] ||
      die "skid provider asset is invalid: $source"
  done
}

skidbladnir_provider_install_helper() {
  local home="$1" candidate="$2" base release stage source uv wrapper marker pin repository revision entry _installed
  pin="$(skidbladnir_native_pin)" || return 1
  IFS=$'\t' read -r repository entry _installed <<<"$pin"
  # The helper follows its repository's default branch and the latest
  # dependencies its project admits; each revision gets its own generation.
  revision="$(git ls-remote "$repository" HEAD | awk '{print $1}')" || return 1
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || return 1
  base="$home/.local/share/skidbladnir/provider-runtime-control"
  # releases/ holds generations from the retired pinned scheme; retained skid
  # generations may still reference them, so new ones never share that space.
  release="$base/generations/$revision"
  uv="$base/bootstrap/bin/uv"
  ensure_directory "$base" 0700 || return 1
  ensure_directory "$base/generations" 0700 || return 1
  if [[ ! -x "$base/bootstrap/bin/python" ]]; then
    python3 -m venv "$base/bootstrap" || return 1
  fi
  PIP_NO_CACHE_DIR=1 "$base/bootstrap/bin/python" -m pip --disable-pip-version-check \
    install --quiet --upgrade uv || return 1
  [[ -x "$uv" ]] || return 1
  marker="$release/.installed"
  if [[ ! -f "$marker" || ! -x "$release/.venv/bin/$entry" ]]; then
    [[ ! -e "$release" && ! -L "$release" ]] || {
      render_result ACTION skid.native "incomplete helper at $release; inspect and remove only that generation, then rerun"
      return 2
    }
    stage="$(mktemp -d "$base/.stage.XXXXXX")" || return 1
    source="$stage/source"
    if ! git init --quiet "$source" ||
       ! git -C "$source" remote add origin "$repository" ||
       ! git -C "$source" fetch --quiet --depth=1 origin "$revision" ||
       ! git -C "$source" checkout --quiet --detach "$revision" ||
       [[ "$(git -C "$source" rev-parse HEAD 2>/dev/null)" != "$revision" ]]; then
      rm -R -- "$stage"
      return 1
    fi
    mv -- "$source" "$release" || { rm -R -- "$stage"; return 1; }
    rmdir -- "$stage" || return 1
    if ! UV_CACHE_DIR="$base/cache" UV_PYTHON_INSTALL_DIR="$base/python" \
       "$uv" sync --project "$release" --upgrade --extra claude-sdk --no-dev; then
      rm -R -- "$release"
      return 1
    fi
    if [[ -e "$release/.venv/bin/claude" || -L "$release/.venv/bin/claude" ]]; then
      rm -R -- "$release"
      return 1
    fi
    if ! install -m 0755 "$(dev_server_assets_dir)/skid-provider/native-control-claude" \
        "$release/.venv/bin/claude"; then
      rm -R -- "$release"
      return 1
    fi
    if ! printf '%s\n' "$revision" >"$release/.installed" ||
       ! chmod 0600 "$release/.installed"; then
      rm -R -- "$release"
      return 1
    fi
    render_result INSTALLED skid.native 'provider helper at its latest revision and dependencies'
  fi
  [[ "$(cat "$marker")" == "$revision" &&
     "$(git -C "$release" rev-parse HEAD 2>/dev/null)" == "$revision" &&
     -f "$release/.venv/bin/claude" && ! -L "$release/.venv/bin/claude" &&
     "$(file_mode "$release/.venv/bin/claude" 2>/dev/null)" == 755 ]] || return 1
  cmp -s "$(dev_server_assets_dir)/skid-provider/native-control-claude" "$release/.venv/bin/claude" || return 1
  local probe
  probe="$(mktemp "$base/.probe.XXXXXX")" || return 1
  if printf '{}\n' | env -i HOME="$home" CODEX_HOME="$home/.codex" \
      PATH="$home/.local/bin:/usr/bin:/bin" "$release/.venv/bin/$entry" >"$probe" 2>/dev/null; then
    rm -f -- "$probe"
    return 1
  fi
  if ! python3 - "$probe" <<'PY'; then
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
assert value == {"ok": False, "error": {"code": "rejected", "dispatch": "not_sent"}}
PY
    rm -f -- "$probe"
    return 1
  fi
  rm -f -- "$probe"
  wrapper="$(mktemp "$base/.wrapper.XXXXXX")" || return 1
  python3 - "$(dev_server_assets_dir)/skid-provider/native-control-launch" \
    "$release/.venv" >"$wrapper" <<'PY' || {
import shlex
import sys

source, environment = sys.argv[1:]
with open(source, encoding="utf-8") as stream:
    template = stream.read()
assert template.count("@ENVIRONMENT_SHELL@") == 1
print(template.replace("@ENVIRONMENT_SHELL@", shlex.quote(environment)), end="")
PY
    rm -f -- "$wrapper"
    return 1
  }
  [[ -d "$candidate/providers" && ! -L "$candidate/providers" ]] || {
    rm -f -- "$wrapper"
    return 1
  }
  cp "$wrapper" "$candidate/providers/native-control" || {
    rm -f -- "$wrapper"
    return 1
  }
  chmod 0755 "$candidate/providers/native-control" || return 1
  rm -f -- "$wrapper"
  probe="$(mktemp "$base/.probe.XXXXXX")" || return 1
  if printf '{}\n' | env -i HOME="$home" \
      CLAUDE_CONFIG_DIR="$home/.claude-work" \
      SKIDBLADNIR_CLAUDE_COMMAND="$home/.local/bin/claude" \
      PATH=/usr/bin:/bin "$candidate/providers/native-control" >"$probe" 2>/dev/null; then
    rm -f -- "$probe"
    return 1
  fi
  if ! python3 - "$probe" <<'PY'; then
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
assert value == {"ok": False, "error": {"code": "rejected", "dispatch": "not_sent"}}
PY
    rm -f -- "$probe"
    return 1
  fi
  rm -f -- "$probe"
}

# A normal host apply must not touch startup files for an optional gateway.
# Skid checks them before staging, then installs its own guarded source.
skidbladnir_shell_setup() {
  local home="$1" operation="$2" login='' path target
  case "$operation" in
  check | install | restore-instant-prompt) ;;
  *) return 64 ;;
  esac
  for path in .bash_profile .bash_login .profile; do
    if [[ -e "$home/$path" || -L "$home/$path" ]]; then
      login="$path"
      break
    fi
  done
  login="${login:-.bash_profile}"
  local -a paths=("$login" .bashrc .zshrc .zlogin)
  [[ "$operation" != restore-instant-prompt ]] || paths=(.zshrc)
  for path in "${paths[@]}"; do
    target="$(python3 - "$home/$path" <<'PY'
import os
import sys

path = sys.argv[1]
target = os.path.realpath(path)
if ((os.path.lexists(path) and not os.path.isfile(target)) or
        "\n" in target or "\r" in target):
    raise SystemExit(1)
print(target)
PY
)" || {
      render_result ACTION skid.shell "startup target is not a regular file: $home/$path"
      return 2
    }
    if [[ "$operation" == restore-instant-prompt && ! -e "$target" ]]; then
      continue
    fi
    skidbladnir_shell_source "$target" "$path" "$operation" || return $?
  done
}

skidbladnir_shell_source() {
  local target="$1" startup="$2" operation="${3:-install}" candidate mode=0644
  if [[ -e "$target" ]]; then
    mode="$(file_mode "$target")" || return 1
  fi
  candidate="$(mktemp "$(dirname "$target")/.skid-shell-init.XXXXXX")" || return 1
  if ! python3 - "$target" "$startup" "$operation" >"$candidate" <<'PY'; then
import sys

path, startup, operation = sys.argv[1:]
instant_begin = b"# dev-server skid instant prompt begin"
instant_end = b"# dev-server skid instant prompt end"
instant_block = (instant_begin + b"\n"
                 b"# the first skid prompt runs a foreground startup action that needs the terminal.\n"
                 b'if [[ ( "${SKIDBLADNIR_SHELL:-}" != 1 || "${SKIDBLADNIR_STARTUP_PID:-}" != "$$" ||\n'
                 b'        "${ZSH_SUBSHELL:-0}" != 0 ) &&\n'
                 b'      -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then\n'
                 b'  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"\n'
                 b'fi\n' + instant_end + b"\n")
instant_original = (b'if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then\n'
                    b'  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"\n'
                    b'fi\n')
zsh_header = (b"# Managed by dev-server bootstrap.\n\n"
              b'if [ -z "${ZSH_VERSION:-}" ]; then\n'
              b'  echo "This file is for zsh. Run \'exec zsh\' or open a new SSH session instead."\n'
              b'  return 0 2>/dev/null || exit 0\n'
              b'fi\n\n')
begin = b"# dev-server skid shell init begin"
end = b"# dev-server skid shell init end"
block = (begin + b"\n"
         b'if [ "${SKIDBLADNIR_SHELL:-}" = 1 ]; then\n'
         b'  . "$HOME/.local/share/skidbladnir/current/providers/shell-init"\n'
         b'elif [ -n "${SKIDBLADNIR_CONNECTION:-}" ] || [ "${SKIDBLADNIR_TERMINAL_CONTEXT:-}" = 1 ]; then\n'
         b'  . "$HOME/.local/share/skidbladnir/current/providers/terminal-context-init"\n'
         b'fi\n' + end + b"\n")
old_block = (begin + b"\n"
             b'if [ "${SKIDBLADNIR_SHELL:-}" = 1 ]; then\n'
             b'  . "$HOME/.local/share/skidbladnir/current/providers/shell-init"\n'
             b'fi\n' + end + b"\n")
old_zsh_guard = (b"# Original skid marks only shells it creates. Source after shared aliases.\n"
                 b'if [[ "${SKIDBLADNIR_SHELL:-}" == 1 ]]; then\n'
                 b'  source "$HOME/.local/share/skidbladnir/current/providers/shell-init"\n'
                 b'fi\n')
try:
    with open(path, "rb") as stream:
        old = stream.read(1048577)
except FileNotFoundError:
    old = b""
if len(old) > 1048576:
    raise SystemExit("shell startup file is too large")
if old.count(instant_begin) > 1 or old.count(instant_end) > 1:
    raise SystemExit("skid instant prompt marker is duplicated")
if (instant_begin in old or instant_end in old) and instant_block not in old:
    raise SystemExit("skid instant prompt block was changed or is incomplete")
if startup == ".zshrc":
    for preamble in (instant_block, instant_original):
        if preamble not in old:
            continue
        head = old.split(preamble, 1)[0]
        if head.startswith(zsh_header):
            head = head[len(zsh_header):]
        if any(line.strip() and not line.lstrip().startswith(b"#") for line in head.splitlines()):
            raise SystemExit("instant prompt preamble must precede startup code after the managed zsh guard")
if operation == "restore-instant-prompt":
    sys.stdout.buffer.write(old.replace(instant_block, instant_original))
    raise SystemExit(0)
if operation not in ("check", "install"):
    raise SystemExit("invalid skid shell installation operation")
if startup == ".zshrc":
    unguarded = old.replace(instant_block, b"")
    if unguarded.count(instant_original) > 1:
        raise SystemExit("instant prompt preamble is duplicated")
    remainder = unguarded.replace(instant_original, b"")
    if b"p10k-instant-prompt-" in remainder:
        raise SystemExit("instant prompt preamble is unsupported; use the managed zsh preamble")
    if instant_block in old and instant_original in unguarded:
        raise SystemExit("instant prompt preamble is duplicated")
    old = old.replace(instant_original, instant_block)
if old.count(begin) > 1 or old.count(end) > 1:
    raise SystemExit("skid shell init marker is duplicated")
owned = next((item for item in (block, old_block) if item in old), b"")
if (begin in old or end in old) and not owned:
    raise SystemExit("skid shell init marker is incomplete")
kept = old.replace(owned, b"") if owned else old
guard_count = old.count(old_zsh_guard)
if startup == ".zshrc" and guard_count:
    if guard_count != 1:
        raise SystemExit("skid zsh guard is duplicated")
    kept = kept.replace(old_zsh_guard, b"")
result = kept + (b"\n" if kept and not kept.endswith(b"\n") else b"") + block
sys.stdout.buffer.write(result)
PY
    rm -f -- "$candidate"
    return 1
  fi
  if [[ "$operation" == check ]]; then
    rm -f -- "$candidate"
    return 0
  fi
  install_managed_file "$candidate" "$target" "$mode" skid.shell || {
    rm -f -- "$candidate"
    return 1
  }
  rm -f -- "$candidate"
}

skidbladnir_provider_apply() {
  local home="$1" stage="$2" target mode plugin
  skidbladnir_provider_preflight "$home" || return $?
  [[ -f "$stage/host-config.json" && ! -L "$stage/host-config.json" ]] ||
    die 'rendered skid provider config is missing'
  dev_server_strict_json_file "$stage/host-config.json" 65536 || die 'rendered skid host config is invalid'
  ai_install_profile_env "$home" || return 1
  skidbladnir_provider_install_helper "$home" "$stage" || return $?
  plugin="$stage/providers/claude-agent-identity"
  mkdir -m 0755 "$plugin" || return 1
  for target in .claude-plugin hooks bin; do
    mkdir -m 0755 "$plugin/$target" || return 1
  done
  for target in .claude-plugin/plugin.json hooks/hooks.json bin/agent-hook; do
    mode=0644
    [[ "$target" != bin/agent-hook ]] || mode=0755
    cp "$(dev_server_assets_dir)/skid-provider/claude-agent-identity/$target" "$plugin/$target" || return 1
    chmod "$mode" "$plugin/$target" || return 1
  done
  skidbladnir_shell_setup "$home" install || return $?
}
