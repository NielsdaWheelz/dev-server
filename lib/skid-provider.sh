#!/usr/bin/env bash

source "$(dirname "${BASH_SOURCE[0]}")/provider-homes.sh"

# The npm javascript launcher selects this same packaged executable. Skid's
# config and product-local command require the native path, not that launcher.
skidbladnir_native_paths() {
  local home="$1" package triple codex claude claude_target
  case "$(uname -s):$(uname -m)" in
  Darwin:arm64) package=codex-darwin-arm64 triple=aarch64-apple-darwin ;;
  Linux:x86_64) package=codex-linux-x64 triple=x86_64-unknown-linux-musl ;;
  *) return 1 ;;
  esac
  codex="$home/.local/lib/node_modules/@openai/codex/node_modules/@openai/$package/vendor/$triple/bin/codex"
  claude="$home/.local/bin/claude"
  [[ -x "$codex" && -f "$codex" && ! -L "$codex" && -L "$claude" && -x "$claude" ]] || return 1
  claude_target="$(readlink "$claude")" || return 1
  [[ "$claude_target" == "$home/.local/share/claude/versions/"* &&
     -f "$claude_target" && ! -L "$claude_target" && -x "$claude_target" ]] || return 1
  printf '%s\t%s\t%s\n' "$codex" "$claude" "$home"
}

skidbladnir_provider_preflight() {
  local home="$1" pin
  local qualification
  pin="$(dev_server_assets_dir)/skid-provider/native-control.json"

  dev_server_strict_json_file "$pin" 4096 || die 'skid native-control pin is invalid'
  qualification="$(python3 - "$pin" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
expected = {
    "repository": "https://github.com/NielsdaWheelz/llm-calling.git",
    "revision": "ec97adeb9ddd0f91b141f89cc42cff7cc7efdb8f",
    "lockSha256": "7566d8859aead7cfa6ae9477f5ea2406d00c860335cbe954cbb320ea330783f5",
    "uvVersion": "0.11.28",
    "pythonVersion": "3.12.13",
    "claudeSdkVersion": "0.2.130",
    "entryPoint": "provider-runtime-control",
    "installedCommand": "skidbladnir-provider-runtime-control",
}
if value.keys() != expected.keys() | {"qualified"}:
    raise SystemExit(1)
if any(value[key] != wanted for key, wanted in expected.items()):
    raise SystemExit(1)
if type(value["qualified"]) is not bool:
    raise SystemExit(1)
print("ready" if value["qualified"] else "pending")
PY
)" || die 'skid native-control pin differs from the historical inputs'
  if [[ "$qualification" == pending ]]; then
    render_result ACTION skid.native 'original skid owner has not qualified the pinned native helper'
    return 2
  fi
  if ! skidbladnir_native_paths "$home" >/dev/null || [[ ! -x "$home/bin/claude-statusline" ]]; then
    render_result ACTION skid.providers 'install the shared native codex, claude, and status line before skid'
    return 2
  fi
  command -v git >/dev/null && command -v python3 >/dev/null || {
    render_result ACTION skid.native 'git and python3 are required for the pinned helper'
    return 2
  }
  for source in native-control-launch native-control-claude provider-command shell-init \
    claude-agent-identity/.claude-plugin/plugin.json \
    claude-agent-identity/hooks/hooks.json claude-agent-identity/bin/agent-hook; do
    [[ -f "$(dev_server_assets_dir)/skid-provider/$source" &&
       ! -L "$(dev_server_assets_dir)/skid-provider/$source" ]] ||
      die "skid provider asset is invalid: $source"
  done
}

skidbladnir_provider_install_helper() {
  local home="$1" candidate="$2" base release stage source uv wrapper marker
  local revision=ec97adeb9ddd0f91b141f89cc42cff7cc7efdb8f
  base="$home/.local/share/skidbladnir/provider-runtime-control"
  release="$base/releases/$revision"
  uv="$base/bootstrap/bin/uv"
  ensure_directory "$base" 0700 || return 1
  ensure_directory "$base/releases" 0700 || return 1
  if [[ ! -x "$uv" || "$("$uv" --version 2>/dev/null)" != 'uv 0.11.28'* ]]; then
    python3 -m venv "$base/bootstrap" || return 1
    PIP_NO_CACHE_DIR=1 "$base/bootstrap/bin/python" -m pip --disable-pip-version-check \
      install --quiet --upgrade 'uv==0.11.28' || return 1
    [[ "$("$uv" --version)" == 'uv 0.11.28'* ]] || return 1
  fi
  marker="$release/.installed"
  if [[ ! -f "$marker" || ! -x "$release/.venv/bin/provider-runtime-control" ]]; then
    [[ ! -e "$release" && ! -L "$release" ]] || {
      render_result ACTION skid.native "incomplete pinned helper at $release; inspect and remove only that generation, then rerun"
      return 2
    }
    stage="$(mktemp -d "$base/.stage.XXXXXX")" || return 1
    source="$stage/source"
    if ! git clone --quiet --no-checkout https://github.com/NielsdaWheelz/llm-calling.git "$source" ||
       ! git -C "$source" fetch --quiet --depth=1 origin "$revision" ||
       ! git -C "$source" checkout --quiet --detach "$revision" ||
       [[ "$(git -C "$source" rev-parse HEAD 2>/dev/null)" != "$revision" ]] ||
       [[ "$(dev_server_sha256 "$source/uv.lock")" != 7566d8859aead7cfa6ae9477f5ea2406d00c860335cbe954cbb320ea330783f5 ]]; then
      rm -R -- "$stage"
      return 1
    fi
    mv -- "$source" "$release" || { rm -R -- "$stage"; return 1; }
    rmdir -- "$stage" || return 1
    if ! UV_CACHE_DIR="$base/cache" UV_PYTHON_INSTALL_DIR="$base/python" \
       "$uv" sync --project "$release" --python 3.12.13 --frozen --extra claude-sdk --no-dev ||
       ! "$release/.venv/bin/python" - <<'PY'
from importlib.metadata import version
import sys

assert sys.version_info[:3] == (3, 12, 13)
assert version("claude-agent-sdk") == "0.2.130"
PY
    then
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
    if ! printf '%s\n' "$revision uv=0.11.28 python=3.12.13 claude-sdk=0.2.130 frozen" >"$release/.installed" ||
       ! chmod 0600 "$release/.installed"; then
      rm -R -- "$release"
      return 1
    fi
    render_result INSTALLED skid.native 'pinned provider helper and frozen sdk environment'
  fi
  [[ "$(cat "$marker")" == "$revision uv=0.11.28 python=3.12.13 claude-sdk=0.2.130 frozen" &&
     "$(git -C "$release" rev-parse HEAD 2>/dev/null)" == "$revision" &&
     "$(dev_server_sha256 "$release/uv.lock")" == 7566d8859aead7cfa6ae9477f5ea2406d00c860335cbe954cbb320ea330783f5 &&
     -f "$release/.venv/bin/claude" && ! -L "$release/.venv/bin/claude" &&
     "$(file_mode "$release/.venv/bin/claude" 2>/dev/null)" == 755 ]] || return 1
  cmp -s "$(dev_server_assets_dir)/skid-provider/native-control-claude" "$release/.venv/bin/claude" || return 1
  "$release/.venv/bin/python" - <<'PY' || return 1
from importlib.metadata import version
import sys

assert sys.version_info[:3] == (3, 12, 13)
assert version("claude-agent-sdk") == "0.2.130"
PY
  local probe
  probe="$(mktemp "$base/.probe.XXXXXX")" || return 1
  if printf '{}\n' | env -i HOME="$home" CODEX_HOME="$home/.local/share/skidbladnir/providers/codex-personal" \
      PATH="$home/.local/bin:/usr/bin:/bin" "$release/.venv/bin/provider-runtime-control" >"$probe" 2>/dev/null; then
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
      CLAUDE_CONFIG_DIR="$home/.local/share/skidbladnir/providers/claude-work" \
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

skidbladnir_provider_apply() {
  local home="$1" stage="$2" target mode account root plugin
  skidbladnir_provider_preflight "$home" || return $?
  [[ -f "$stage/host-config.json" && ! -L "$stage/host-config.json" &&
     -f "$stage/agent-hooks.json" && ! -L "$stage/agent-hooks.json" ]] ||
    die 'rendered skid provider config or hooks are missing'
  dev_server_strict_json_file "$stage/host-config.json" 65536 || die 'rendered skid host config is invalid'
  dev_server_strict_json_file "$stage/agent-hooks.json" 16384 || die 'rendered skid codex hooks are invalid'
  provider_homes_prepare "$home" skidbladnir || return 1
  skidbladnir_provider_install_helper "$home" "$stage" || return $?
  root="$home/.local/share/skidbladnir/providers"
  for account in codex-personal codex-work codex-work2; do
    install_managed_file "$stage/agent-hooks.json" "$root/$account/hooks.json" 0600 skid.integration || return 1
  done
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
}
