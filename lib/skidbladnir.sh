#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034 # dynamic sibling sources and explicit gateway context.

# The original tmux gateway owns only the skidbladnir namespace.
if ! declare -F gateway_apply >/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/gateway-runtime.sh"
fi
: "${dev_server_gateway_port:=7341}"

skidbladnir_render_configs() {
  local platform="$1" stage="$2" assets home tmux_path tmux_version native codex claude native_home
  assets="$(dev_server_assets_dir)"
  home="$(dev_server_home)"
  [[ "$home" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "invalid deployment root: $home"
  native="$(skidbladnir_native_paths "$home")" || return 1
  IFS=$'\t' read -r codex claude native_home <<<"$native"
  [[ "$native_home" == "$home" ]] || return 1
  case "$platform" in
  macos) tmux_path=/opt/homebrew/bin/tmux; platform=Darwin ;;
  arch | devbox) tmux_path=/usr/bin/tmux; platform=Linux ;;
  *) return 1 ;;
  esac
  [[ -x "$tmux_path" ]] || return 1
  tmux_version="$("$tmux_path" -V)" || return 1
  [[ "$tmux_version" =~ ^tmux\ [0-9] ]] || return 1
  python3 - "$assets" "$platform" "$home" "$stage" "$tmux_path" "$tmux_version" "$codex" "$claude" <<'PY'
import json
from pathlib import Path
import re
import shlex
import sys

assets, platform, home, stage, tmux_path, tmux_version, codex, claude = sys.argv[1:]
assets = Path(assets)
replacements = {
    "ROOT": home,
    "PLATFORM": platform,
    "TMUX": tmux_path,
    "TMUX_VERSION": tmux_version,
    "CODEX": codex,
    "CLAUDE": claude,
    "HOOK_COMMAND": shlex.join([f"{home}/.local/bin/skidbladnir", "agent-hook",
                                f"--host-config={home}/.local/share/skidbladnir/current/host-config.json",
                                "Codex", "SessionStart"]),
}
def render(name):
    value = json.loads((assets / "skidbladnir" / name).read_text())
    def replace(item):
        if isinstance(item, dict):
            return {key: replace(child) for key, child in item.items()}
        if isinstance(item, list):
            return [replace(child) for child in item]
        if isinstance(item, str):
            return re.sub(r"@([A-Z_0-9]+)@",
                          lambda match: replacements[match[1]], item)
        return item
    value = replace(value)
    Path(stage, name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    return value

value = render("host-config.json")
expected = f"{home}/.local/share/skidbladnir/providers"
if (set(value) != {"platform", "tmux", "nativeControlPath", "profiles"} or
        value["nativeControlPath"] != f"{home}/.local/bin/skidbladnir-provider-runtime-control" or
        value["tmux"] != {"path": tmux_path, "testedVersion": tmux_version} or
        [row.get("key") for row in value["profiles"]] !=
        ["personal", "work", "work2", "claude-work"]):
    raise SystemExit("skid host configuration differs from deployment contract")
for row in value["profiles"]:
    key = row["key"]
    leaf = f"codex-{key}" if key != "claude-work" else "claude-work"
    if row["environment"] != [{"name": "CODEX_HOME" if key != "claude-work" else "CLAUDE_CONFIG_DIR",
                               "value": f"{expected}/{leaf}"}]:
        raise SystemExit("skid provider home is outside its namespace")
render("agent-hooks.json")
providers = Path(stage, "providers")
providers.mkdir(mode=0o700)
command = (assets / "skid-provider/provider-command").read_text()
for token, value in {"ROOT_SHELL": home, "CODEX_SHELL": codex,
                     "CLAUDE_SHELL": claude}.items():
    command = command.replace(f"@{token}@", shlex.quote(value))
if re.search(r"@[A-Z_]+@", command):
    raise SystemExit("unrendered skid provider command")
(providers / "provider-command").write_text(command)
(providers / "shell-init").write_bytes((assets / "skid-provider/shell-init").read_bytes())
PY
}

skidbladnir_generation_config_valid() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
raise SystemExit(0 if isinstance(value, dict) and "tmux" in value and
                 "nativeControlPath" in value and "herdr" not in value else 1)
PY
}

skidbladnir_apply() {
  if ! declare -F skidbladnir_provider_apply >/dev/null; then
    source "$(dirname "${BASH_SOURCE[0]}")/skid-provider.sh"
  fi
  : "${skidbladnir_release_pin_file:=$(dev_server_assets_dir)/skidbladnir/release-pin.json}"
  gateway_name=skidbladnir
  gateway_repository=NielsdaWheelz/skidbladnir
  gateway_release_pin_file="$skidbladnir_release_pin_file"
  gateway_port="$dev_server_gateway_port"
  gateway_receipt=skid
  gateway_machine_header=Skidbladnir-Machine
  gateway_config_renderer=skidbladnir_render_configs
  gateway_generation_validator=skidbladnir_generation_config_valid
  gateway_required_port=7341
  gateway_provider_preflight=skidbladnir_provider_preflight
  gateway_provider_apply=skidbladnir_provider_apply
  gateway_apply "$@"
}

skidbladnir_remove() {
  gateway_name=skidbladnir
  gateway_receipt=skid
  gateway_generation_validator=skidbladnir_generation_config_valid
  gateway_remove "$@"
}
