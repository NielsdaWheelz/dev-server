#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034 # dynamic sibling sources and explicit gateway context.

# The original tmux gateway owns only the skidbladnir namespace.
if ! declare -F gateway_apply >/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/gateway-runtime.sh"
fi
: "${dev_server_gateway_port:=7341}"

skidbladnir_render_configs() {
  local platform="$1" stage="$2" assets home tmux_path tmux_version native codex claude native_home zoxide_path ssh_path mosh_path
  assets="$(dev_server_assets_dir)"
  home="$(dev_server_home)"
  [[ "$home" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "invalid deployment root: $home"
  native="$(skidbladnir_native_paths "$home")" || return 1
  IFS=$'\t' read -r codex claude native_home <<<"$native"
  [[ "$native_home" == "$home" ]] || return 1
  # macos redacts the environment of its platform ssh binary from the gateway.
  case "$platform" in
  macos) tmux_path=/opt/homebrew/bin/tmux; ssh_path=/opt/homebrew/opt/openssh/bin/ssh; platform=Darwin ;;
  arch | devbox) tmux_path=/usr/bin/tmux; ssh_path="$(type -P ssh)" || return 1; platform=Linux ;;
  *) return 1 ;;
  esac
  [[ -x "$tmux_path" ]] || return 1
  zoxide_path="$(type -P zoxide)" || return 1
  mosh_path="$(type -P mosh)" || return 1
  [[ "$zoxide_path" == /* && "$ssh_path" == /* && "$mosh_path" == /* && -x "$zoxide_path" && -x "$ssh_path" && -x "$mosh_path" ]] || return 1
  tmux_version="$("$tmux_path" -V)" || return 1
  [[ "$tmux_version" =~ ^tmux\ [0-9] ]] || return 1
  python3 - "$assets" "$platform" "$home" "$stage" "$tmux_path" "$tmux_version" "$codex" "$claude" "$zoxide_path" "$ssh_path" "$mosh_path" <<'PY'
import json
from pathlib import Path
import re
import shlex
import sys

assets, platform, home, stage, tmux_path, tmux_version, codex, claude, zoxide, ssh, mosh = sys.argv[1:]
assets = Path(assets)
replacements = {
    "ROOT": home,
    "PLATFORM": platform,
    "TMUX": tmux_path,
    "TMUX_VERSION": tmux_version,
    "CODEX": codex,
    "CLAUDE": claude,
    "ZOXIDE": zoxide,
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
if (set(value) != {"platform", "tmux", "nativeControlPath", "zoxidePath", "profiles"} or
        value["nativeControlPath"] != f"{home}/.local/bin/skidbladnir-provider-runtime-control" or
        value["zoxidePath"] != zoxide or
        value["tmux"] != {"path": tmux_path, "testedVersion": tmux_version} or
        [row.get("key") for row in value["profiles"]] !=
        ["personal", "work", "work2", "claude-work"]):
    raise SystemExit("skid host configuration differs from deployment contract")
accounts = {"personal": ("CODEX_HOME", ".codex"),
            "work": ("CODEX_HOME", ".codex-work"),
            "work2": ("CODEX_HOME", ".codex-work2"),
            "claude-work": ("CLAUDE_CONFIG_DIR", ".claude-work")}
for row in value["profiles"]:
    name, leaf = accounts[row["key"]]
    if row["environment"] != [{"name": name, "value": f"{home}/{leaf}"}]:
        raise SystemExit("skid provider home differs from existing account")
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
context = (assets / "skid-provider/terminal-context-init").read_text()
for token, value in {"SSH_SHELL": ssh, "MOSH_SHELL": mosh}.items():
    context = context.replace(f"@{token}@", shlex.quote(value))
if re.search(r"@[A-Z_]+@", context):
    raise SystemExit("unrendered terminal context command")
(providers / "terminal-context-init").write_text(context)
PY
}

skidbladnir_generation_config_valid() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
raise SystemExit(0 if isinstance(value, dict) and "tmux" in value and
                 "nativeControlPath" in value else 1)
PY
}

# Stage the devbox cli using the gateway's existing pin and artifact admission.
# The caller owns this temporary directory and removes it after reconciliation.
skidbladnir_prepare_cli_artifact() {
  local stage="$1" pin_line version source_sha url archive_sha platform artifact
  gateway_name=skidbladnir
  gateway_repository=NielsdaWheelz/skidbladnir
  gateway_release_pin_file="$(dev_server_assets_dir)/skidbladnir/release-pin.json"
  pin_line="$(gateway_release_values devbox)" || die 'skid release pin is invalid'
  IFS=$'\t' read -r version source_sha url archive_sha platform <<<"$pin_line"
  artifact="$(dev_server_home)/.local/share/skidbladnir/artifacts/$archive_sha"
  if [[ ! -e "$artifact" && ! -L "$artifact" ]]; then
    artifact="$stage/admitted-artifact"
  fi
  gateway_prepare_artifact "$stage" "$version" "$source_sha" "$url" \
    "$archive_sha" "$platform" "$artifact" || die 'could not admit the devbox cli artifact'
  printf '%s\n' "$artifact"
}

# A fixed cli and the gateway it speaks to change only while jarvis is paused
# and cleanly stopped. Identical executables require no service operation.
skidbladnir_jarvis_preflight() {
  local candidate="$1" installed="$2" gateway_binary="$3" paused="$4"
  [[ -f "$candidate" && ! -L "$candidate" ]] || die 'invalid admitted cli executable'
  [[ ! -L "$installed" && ( ! -e "$installed" || -f "$installed" ) ]] ||
    die 'jarvis cli target is not a regular file'
  if python3 - "$candidate" "$installed" "$gateway_binary" <<'PYTHON'
from pathlib import Path
import stat
import sys
candidate, installed, gateway = map(Path, sys.argv[1:])
if not candidate.is_file() or candidate.is_symlink():
    raise SystemExit("invalid admitted cli executable")
try:
    info = installed.lstat()
    same = (stat.S_ISREG(info.st_mode) and info.st_uid == 0 and info.st_gid == 0
            and stat.S_IMODE(info.st_mode) == 0o755
            and installed.read_bytes() == candidate.read_bytes()
            and gateway.is_file() and gateway.read_bytes() == candidate.read_bytes())
except OSError:
    same = False
raise SystemExit(0 if same else 1)
PYTHON
  then
    return 0
  fi
  if [[ "$(systemctl show --property=ActiveState --value jarvis.service)" != inactive ||
    "$(systemctl show --property=Result --value jarvis.service)" != success ||
    "$(systemctl show --property=MainPID --value jarvis.service)" != 0 ]]; then
    render_result ACTION jarvis.agent-cli 'executable change requires jarvis paused and cleanly stopped before gateway activation'
    return 2
  fi
  if ! python3 - "$paused" <<'PYTHON'
import json
from pathlib import Path
import sys
path = Path(sys.argv[1])
try:
    value = json.loads(path.read_text()) if path.is_file() and not path.is_symlink() else None
except (OSError, ValueError):
    value = None
raise SystemExit(0 if isinstance(value, dict) and set(value) == {"paused", "schema_version"}
                 and value["paused"] is True and value["schema_version"] == "jarvis-paused.v1" else 1)
PYTHON
  then
    render_result ACTION jarvis.agent-cli 'prepare jarvis paused state before executable activation'
    return 2
  fi
}

skidbladnir_install_jarvis_cli() {
  local candidate="$1" installed="$2"
  [[ "$(id -u)" == 0 ]] || die 'jarvis cli installation requires root'
  [[ ! -L "$installed" && ( ! -e "$installed" || -f "$installed" ) ]] ||
    die 'jarvis cli target is not a regular file'
  atomic_install_file "$candidate" "$installed" 0755 || return 1
  if [[ "$(stat -c '%u|%g' "$installed")" != '0|0' ]]; then
    chown root:root "$installed" || return 1
    dev_server_install_status=CHANGED
  fi
  [[ "$(stat -c '%u|%g|%a' "$installed")" == '0|0|755' ]] || return 1
  if [[ "${dev_server_install_status:-UP TO DATE}" != 'UP TO DATE' ]]; then
    render_result "$dev_server_install_status" jarvis.agent-cli 'admitted skid executable installed'
  fi
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
