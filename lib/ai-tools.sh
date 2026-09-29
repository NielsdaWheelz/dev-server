#!/usr/bin/env bash

ai_require_codex_runtime() {
  require_cmd python3 git
}

ai_codex_source_pin() {
  local pin
  pin="$(dev_server_assets_dir)/codex/native-source.json"
  dev_server_strict_json_file "$pin" 4096 || return 1
  python3 - "$pin" <<'PIN'
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
fields = {"repository", "revision", "version", "baseLockSha256", "patchSha256", "lockSha256", "rustVersion"}
if not isinstance(value, dict) or value.keys() != fields:
    raise SystemExit(1)
if not isinstance(value["repository"], str) or not re.fullmatch(r"https://[a-zA-Z0-9./_-]+\.git", value["repository"]):
    raise SystemExit(1)
for key, size in (("revision", 40), ("baseLockSha256", 64), ("patchSha256", 64), ("lockSha256", 64)):
    if not isinstance(value[key], str) or not re.fullmatch(r"[0-9a-f]{%d}" % size, value[key]):
        raise SystemExit(1)
for key in ("version", "rustVersion"):
    if not isinstance(value[key], str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", value[key]):
        raise SystemExit(1)
print("\t".join(value[key] for key in ("repository", "revision", "version", "baseLockSha256", "patchSha256", "lockSha256", "rustVersion")))
PIN
}

ai_claude_version_pin() {
  local pin
  pin="$(dev_server_assets_dir)/skid-provider/native-control.json"
  dev_server_strict_json_file "$pin" 4096 || return 1
  python3 - "$pin" <<'PIN'
import json
import re
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
version = value.get("claudeVersion") if isinstance(value, dict) else None
if not isinstance(version, str) or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
    raise SystemExit(1)
print(version)
PIN
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
  ai_codex_source_pin >/dev/null || die 'invalid native Codex source pin'
  ai_claude_version_pin >/dev/null || die 'invalid qualified Claude version'
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

# The managed generation is immutable; consumers receive its native executable.
_ai_codex_generation_path() {
  local home="$1" pin repository revision version base_lock patch lock rust release
  pin="$(ai_codex_source_pin)" || return 1
  IFS=$'\t' read -r repository revision version base_lock patch lock rust <<<"$pin"
  release="$home/.local/share/codex/releases/$revision-$patch"
  [[ -f "$release/bin/codex" && ! -L "$release/bin/codex" && -x "$release/bin/codex" &&
    -f "$release/.installed" && ! -L "$release/.installed" &&
    "$(cat "$release/.installed")" == "$(dev_server_sha256 "$(dev_server_assets_dir)/codex/native-source.json")" ]] || return 1
  [[ -f "$release/codex-package.json" && ! -L "$release/codex-package.json" &&
    -x "$release/bin/codex-code-mode-host" && -x "$release/codex-path/rg" &&
    -f "$release/LICENSE" && -f "$release/NOTICE" ]] || return 1
  if [[ "$(uname -s)" == Linux ]]; then
    [[ -x "$release/codex-resources/bwrap" ]] || return 1
  fi
  python3 - "$release/codex-package.json" "$version" <<'PACKAGE' || return 1
import json
import sys
with open(sys.argv[1], encoding="utf-8") as stream:
    value = json.load(stream)
if value.get("version") != sys.argv[2] or value.get("skidPinned") is not True:
    raise SystemExit(1)
PACKAGE
  [[ "$("$release/bin/codex" --version)" == "codex-cli $version" ]] || return 1
  printf '%s\n' "$release/bin/codex"
}

ai_codex_installed_path() {
  local home="$1" binary generation
  generation="$(_ai_codex_generation_path "$home")" || return 1
  binary="$home/.local/bin/codex"
  [[ -L "$binary" && "$(readlink "$binary")" == "$generation" ]] || return 1
  printf '%s\n' "$generation"
}

ai_install_codex() (
  local home pin repository revision version base_lock patch lock rust base release stage='' source binary status=INSTALLED command generation target v8 archive binding checksums expected
  home="$(dev_server_home)"
  pin="$(ai_codex_source_pin)" || die 'invalid native Codex source pin'
  IFS=$'\t' read -r repository revision version base_lock patch lock rust <<<"$pin"
  [[ "$(dev_server_sha256 "$(dev_server_assets_dir)/codex/native-agent.patch")" == "$patch" ]] ||
    die 'native Codex patch checksum differs'
  if ai_codex_installed_path "$home" >/dev/null; then
    return 0
  fi
  if generation="$(_ai_codex_generation_path "$home")"; then
    dev_server_atomic_symlink "$home/.local/bin/codex" "$generation" || return 1
    render_result UPDATED "AI tool" "codex@$version native source"
    return 0
  fi
  for command in rustup cmake pkg-config cc rg curl; do
    if ! command -v "$command" >/dev/null; then
      render_result ACTION codex.build "install the declared source-build prerequisite: $command"
      return 2
    fi
  done
  if [[ "$(uname -s)" == Linux ]] && ! command -v bwrap >/dev/null; then
    render_result ACTION codex.build 'install the declared source-build prerequisite: bwrap'
    return 2
  fi
  base="$home/.local/share/codex"
  release="$base/releases/$revision-$patch"
  binary="$home/.local/bin/codex"
  if [[ -e "$binary" || -L "$binary" ]]; then
    status=UPDATED
  fi
  if [[ -e "$release" || -L "$release" ]]; then
    render_result ACTION codex.build "incomplete or changed managed generation: $release; inspect and remove only that generation, then rerun"
    return 2
  fi
  ensure_directory "$base" 0755 || return 1
  ensure_directory "$base/releases" 0755 || return 1
  stage="$(mktemp -d "$base/.stage.XXXXXX")" || return 1
  trap '[[ -z "$stage" ]] || rm -R -- "$stage"' EXIT
  source="$stage/source"
  git init --quiet "$source" || return 1
  git -C "$source" remote add origin "$repository" || return 1
  git -C "$source" fetch --quiet --depth=1 origin "$revision" || return 1
  git -C "$source" checkout --quiet --detach "$revision" || return 1
  [[ "$(git -C "$source" rev-parse HEAD)" == "$revision" &&
  "$(dev_server_sha256 "$source/codex-rs/Cargo.lock")" == "$base_lock" ]] || return 1
  git -C "$source" apply --check "$(dev_server_assets_dir)/codex/native-agent.patch" || return 1
  git -C "$source" apply "$(dev_server_assets_dir)/codex/native-agent.patch" || return 1
  [[ "$(dev_server_sha256 "$source/codex-rs/Cargo.lock")" == "$lock" ]] || return 1
  rustup toolchain install "$rust" --profile minimal || return 1
  [[ "$(rustup run "$rust" rustc --version)" == "rustc $rust "* ]] || return 1
  target="$(rustup run "$rust" rustc -vV | sed -n 's/^host: //p')" || return 1
  [[ "$target" == *-apple-darwin || "$target" == *-unknown-linux-gnu ]] || return 1
  # Use upstream's sandbox-enabled V8 artifacts, authenticated by the pinned tree.
  v8="$(python3 "$source/.github/scripts/rusty_v8_bazel.py" resolved-v8-crate-version)" || return 1
  archive="librusty_v8_ptrcomp_sandbox_release_${target}.a.gz"
  binding="src_binding_ptrcomp_sandbox_release_${target}.rs"
  checksums="rusty_v8_ptrcomp_sandbox_release_${target}.sha256"
  mkdir "$stage/v8" || return 1
  curl --proto '=https' --tlsv1.2 -fsSL "https://github.com/openai/codex/releases/download/rusty-v8-v$v8/$checksums" -o "$stage/v8/$checksums" || return 1
  expected="$(awk -v name="$checksums" '$2 == name {print $1}' "$source/third_party/v8/rusty_v8_${v8//./_}_release_manifests.sha256")" || return 1
  [[ "$expected" =~ ^[0-9a-f]{64}$ && "$(dev_server_sha256 "$stage/v8/$checksums")" == "$expected" ]] || return 1
  curl --proto '=https' --tlsv1.2 -fsSL "https://github.com/openai/codex/releases/download/rusty-v8-v$v8/$archive" -o "$stage/v8/$archive" || return 1
  curl --proto '=https' --tlsv1.2 -fsSL "https://github.com/openai/codex/releases/download/rusty-v8-v$v8/$binding" -o "$stage/v8/$binding" || return 1
  python3 - "$stage/v8" "$checksums" "$archive" "$binding" <<'V8_CHECK' || return 1
import hashlib, pathlib, sys
root = pathlib.Path(sys.argv[1])
entries = [line.split() for line in (root / sys.argv[2]).read_text().splitlines()]
if len(entries) != 2 or {entry[1] for entry in entries if len(entry) == 2} != set(sys.argv[3:]):
    raise SystemExit("invalid V8 artifact manifest")
for digest, name in entries:
    if hashlib.sha256((root / name).read_bytes()).hexdigest() != digest:
        raise SystemExit("V8 artifact checksum differs")
V8_CHECK
  RUSTY_V8_ARCHIVE="$stage/v8/$archive" RUSTY_V8_SRC_BINDING_PATH="$stage/v8/$binding" \
    CARGO_TARGET_DIR="$stage/target" rustup run "$rust" cargo build \
    --manifest-path "$source/codex-rs/Cargo.toml" --locked --release --bin codex --bin codex-code-mode-host || return 1
  [[ "$(dev_server_sha256 "$source/codex-rs/Cargo.lock")" == "$lock" &&
  "$("$stage/target/release/codex" --version)" == "codex-cli $version" ]] || return 1
  mkdir -m 0755 "$stage/release" "$stage/release/bin" \
    "$stage/release/codex-path" "$stage/release/codex-resources" || return 1
  install -m 0644 "$source/LICENSE" "$stage/release/LICENSE" || return 1
  install -m 0644 "$source/NOTICE" "$stage/release/NOTICE" || return 1
  install -m 0755 "$stage/target/release/codex" "$stage/release/bin/codex" || return 1
  install -m 0755 "$stage/target/release/codex-code-mode-host" "$stage/release/bin/codex-code-mode-host" || return 1
  install -m 0755 "$(command -v rg)" "$stage/release/codex-path/rg" || return 1
  if [[ "$target" == *-unknown-linux-gnu ]]; then
    install -m 0755 "$(command -v bwrap)" "$stage/release/codex-resources/bwrap" || return 1
  fi
  python3 - "$stage/release/codex-package.json" "$version" "$target" <<'PACKAGE' || return 1
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as stream:
    json.dump({"layoutVersion": 1, "version": sys.argv[2], "target": sys.argv[3],
               "variant": "codex", "skidPinned": True, "entrypoint": "bin/codex",
               "resourcesDir": "codex-resources", "pathDir": "codex-path"}, stream)
    stream.write("\n")
PACKAGE
  chmod 0644 "$stage/release/codex-package.json" || return 1
  dev_server_sha256 "$(dev_server_assets_dir)/codex/native-source.json" >"$stage/release/.installed" || return 1
  chmod 0600 "$stage/release/.installed" || return 1
  mv "$stage/release" "$release" || return 1
  dev_server_atomic_symlink "$binary" "$release/bin/codex" || return 1
  ai_codex_installed_path "$home" >/dev/null || return 1
  render_result "$status" "AI tool" "codex@$version native source"
)

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
  local installer expected

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
  expected="$(ai_claude_version_pin)" || die "invalid qualified Claude version"
  HOME="$home" bash "$installer" "$expected" ||
    die "Claude native installation failed"
)

ai_install_claude() {
  local before
  local binary
  local home
  local status
  local version expected

  expected="$(ai_claude_version_pin)" || die "invalid qualified Claude version"
  home="$(dev_server_home)"
  binary="$(ai_claude_binary)"
  if before="$(ai_claude_native_version)"; then
    [[ "$before" != "$expected" ]] || return 0
    HOME="$home" "$binary" install "$expected" ||
      die "Claude qualified native version reconciliation failed"
    version="$(ai_claude_native_version)" ||
      die "Claude native reconciliation produced an invalid installation"
    [[ "$version" == "$expected" ]] || die "Claude installation differs from qualified version"
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
  [[ "$version" == "$expected" ]] || die "Claude installation differs from qualified version"
  render_result "$status" "AI tool" "claude@$version"
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
  ai_require_codex_runtime || return $?
  ai_validate_inputs
  ai_install_dirs || return 1
  ai_install_claude_settings || return 1
  ai_install_codex || return $?
  ai_install_claude || return 1
  ai_install_profiles || return 1
  ai_install_instructions || return 1
}
