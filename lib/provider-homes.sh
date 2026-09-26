#!/usr/bin/env bash

# Original skid's five private provider homes.
provider_homes_prepare() {
  local home="$1" product="$2" root account directory settings candidate
  local instructions
  local statusline="$home/bin/claude-statusline"

  instructions="$(dev_server_assets_dir)/agent-instructions.md"

  case "$product" in
  skidbladnir) ;;
  *) die "invalid provider-home owner: $product" ;;
  esac
  [[ -f "$instructions" && ! -L "$instructions" && -s "$instructions" ]] ||
    die 'provider instructions are missing'
  [[ -x "$statusline" && ! -L "$statusline" ]] ||
    die "claude status line is not installed: $statusline"
  root="$home/.local/share/$product/providers"
  ensure_directory "$root" 0700 || return 1
  for account in codex-personal codex-work codex-work2 claude-personal claude-work; do
    directory="$root/$account"
    ensure_directory "$directory" 0700 || return 1
    case "$account" in
    codex-*) install_managed_file "$instructions" "$directory/AGENTS.md" 0600 "$product.instructions" || return 1 ;;
    claude-*)
      install_managed_file "$instructions" "$directory/CLAUDE.md" 0600 "$product.instructions" || return 1
      settings="$directory/settings.json"
      candidate="$(mktemp "$directory/.settings.json.XXXXXX")" || return 1
      if ! python3 - "$settings" "$statusline" >"$candidate" <<'PY'; then
import json
import os
import stat
import sys

path, script = sys.argv[1:]

def unique(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError("duplicate settings key")
        value[key] = item
    return value

try:
    info = os.lstat(path)
except FileNotFoundError:
    value = {}
else:
    if not stat.S_ISREG(info.st_mode) or info.st_size > 1048576:
        raise SystemExit("invalid claude settings")
    with open(path, encoding="utf-8") as stream:
        value = json.load(stream, object_pairs_hook=unique,
                          parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
if not isinstance(value, dict):
    raise SystemExit("claude settings must be an object")
value["statusLine"] = {"type": "command", "command": script}
value["autoUpdatesChannel"] = "latest"
value.pop("minimumVersion", None)
json.dump(value, sys.stdout, indent=2, ensure_ascii=False)
sys.stdout.write("\n")
PY
        rm -f -- "$candidate"
        return 1
      fi
      if ! install_managed_file "$candidate" "$settings" 0600 "$product.claude.settings"; then
        rm -f -- "$candidate"
        return 1
      fi
      rm -f -- "$candidate" || return 1
      ;;
    esac
  done
}
