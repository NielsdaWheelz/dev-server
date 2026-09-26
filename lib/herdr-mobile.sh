#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034 # dynamic sibling sources and explicit gateway context.

# The herdr phone gateway owns only the herdr-mobile namespace.
if ! declare -F gateway_apply >/dev/null; then
  source "$(dirname "${BASH_SOURCE[0]}")/gateway-runtime.sh"
fi

: "${dev_server_mobile_gateway_port:=7342}"

herdr_mobile_render_configs() {
  local platform="$1" stage="$2" assets home
  assets="$(dev_server_assets_dir)"
  home="$(dev_server_home)"
  [[ "$home" =~ ^/[A-Za-z0-9._/-]+$ ]] || die "invalid deployment root: $home"
  python3 - "$assets" "$platform" "$home" "$stage" <<'PY'
import json
from pathlib import Path
import re
import sys

assets, platform, home, stage = sys.argv[1:]
assets = Path(assets)
template = (assets / "herdr-mobile/host-config.json").read_text()
replacements = {"ROOT": home,
                "PLATFORM": {"macos": "Darwin", "arch": "Linux", "devbox": "Linux"}[platform]}
rendered = re.sub(r"@([A-Z_0-9]+)@",
                  lambda match: json.dumps(replacements[match[1]])[1:-1], template)
value = json.loads(rendered)
expected = {"path": f"{home}/.local/share/herdr/current/herdr",
            "socketPath": f"{home}/.config/herdr/herdr.sock",
            "testedVersion": "herdr 0.9.1"}
if value["herdr"] != expected:
    raise SystemExit("herdr runtime declaration differs from its pin")
homes = {"personal": ".codex", "work": ".codex-work",
         "work2": ".codex-work2", "claude-work": ".claude-work"}
if [row.get("key") for row in value["profiles"]] != list(homes):
    raise SystemExit("herdr profile order differs from its published contract")
for row in value["profiles"]:
    key = row["key"]
    name = "CODEX_HOME" if key != "claude-work" else "CLAUDE_CONFIG_DIR"
    if row["environment"] != [{"name": name,
                               "value": f"{home}/{homes[key]}"}]:
        raise SystemExit("herdr provider home differs from the existing account map")
Path(stage, "host-config.json").write_text(rendered)
PY
}

herdr_mobile_generation_config_valid() {
  python3 - "$1" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
raise SystemExit(0 if isinstance(value, dict) and "herdr" in value and
                 "tmux" not in value and "nativeControlPath" not in value else 1)
PY
}

herdr_mobile_apply() {
  : "${herdr_mobile_release_pin_file:=$(dev_server_assets_dir)/herdr-mobile/release-pin.json}"
  gateway_name=herdr-mobile
  gateway_repository=NielsdaWheelz/herdr-mobile
  gateway_release_pin_file="$herdr_mobile_release_pin_file"
  gateway_port="$dev_server_mobile_gateway_port"
  gateway_receipt=herdr-mobile
  gateway_machine_header=Herdr-Mobile-Machine
  gateway_config_renderer=herdr_mobile_render_configs
  gateway_generation_validator=herdr_mobile_generation_config_valid
  gateway_required_port=7342
  gateway_provider_preflight=''
  gateway_provider_apply=''
  gateway_apply "$@"
}

herdr_mobile_remove() {
  gateway_name=herdr-mobile
  gateway_receipt=herdr-mobile
  gateway_generation_validator=herdr_mobile_generation_config_valid
  gateway_remove "$@"
}
