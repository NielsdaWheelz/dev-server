#!/usr/bin/env bash

ai_assets_dir() {
  printf '%s/ai\n' "$(dev_server_assets_dir)"
}

ai_install_root() {
  printf '%s/.local/share/dev-server/ai-tools\n' "$(dev_server_home)"
}

ai_require_runtime() {
  local npm_version

  require_cmd node
  require_cmd npm
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' ||
    die "AI tools require Node.js 24 or newer"
  npm_version="$(npm --version)" || die "could not read the npm version"
  node - "$npm_version" <<'NODE' || die "AI tools require npm 11.17.0 or newer"
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
  local assets
  local lock
  local manifest
  local profile

  require_cmd python3

  assets="$(ai_assets_dir)"
  manifest="$assets/package.json"
  lock="$assets/package-lock.json"
  profile="$(dev_server_assets_dir)/routers/ai-profile"
  [[ -f "$manifest" && ! -L "$manifest" ]] ||
    die "invalid AI package manifest: $manifest"
  [[ -f "$lock" && ! -L "$lock" ]] ||
    die "invalid AI package lock: $lock"
  [[ -f "$profile" && ! -L "$profile" ]] ||
    die "invalid AI profile wrapper: $profile"

  python3 - "$manifest" "$lock" <<'PY' || die "invalid AI package declaration"
import json
import re
import sys

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON key: {key}")
        value[key] = item
    return value

def reject_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")

def load(path):
    with open(path, "r", encoding="utf-8") as stream:
        return json.load(stream, object_pairs_hook=unique_object,
                         parse_constant=reject_constant)

manifest = load(sys.argv[1])
lock = load(sys.argv[2])
names = ["@anthropic-ai/claude-code", "@openai/codex"]
dependencies = manifest.get("dependencies")
if (manifest.get("private") is not True or not isinstance(dependencies, dict) or
        sorted(dependencies) != names):
    raise SystemExit(1)
if any(not isinstance(dependencies[name], str) or
       not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", dependencies[name]) for name in names):
    raise SystemExit(1)
allowed = {
    f"@anthropic-ai/claude-code@{dependencies['@anthropic-ai/claude-code']}": True
}
packages = lock.get("packages")
if (manifest.get("allowScripts") != allowed or lock.get("lockfileVersion") != 3 or
        not isinstance(packages, dict) or
        not isinstance(packages.get(""), dict) or
        packages[""].get("dependencies") != dependencies):
    raise SystemExit(1)
scripted = []
for path, entry in packages.items():
    if path == "":
        continue
    if (not isinstance(entry, dict) or
            not re.match(r"^https://registry\.npmjs\.org/", entry.get("resolved", "")) or
            not re.fullmatch(r"sha512-[A-Za-z0-9+/]+={0,2}", entry.get("integrity", ""))):
        raise SystemExit(1)
    if entry.get("hasInstallScript") is True:
        scripted.append(f"{path}@{entry.get('version', '')}")
claude = (
    "node_modules/@anthropic-ai/claude-code@" +
    dependencies["@anthropic-ai/claude-code"]
)
if scripted != [claude]:
    raise SystemExit(1)
PY
}

ai_install_dirs() {
  local home

  home="$(dev_server_home)"
  ensure_directory "$home/bin" 0755 || return 1
  ensure_directory "$home/.local" 0755 || return 1
  ensure_directory "$home/.local/share" 0755 || return 1
  ensure_directory "$home/.local/share/dev-server" 0755 || return 1
  ensure_directory "$(ai_install_root)" 0755 || return 1
  ensure_directory "$home/.codex-work" 0700 || return 1
  ensure_directory "$home/.codex-work2" 0700 || return 1
  ensure_directory "$home/.claude-work" 0700 || return 1
}

ai_package_version() {
  local manifest="$1"
  local package="$2"

  node -e '
    const manifest = require(process.argv[1]);
    const packageName = process.argv[2];
    const version = manifest.name === packageName
      ? manifest.version
      : manifest.dependencies?.[packageName];
    if (typeof version !== "string" || !/^\d+\.\d+\.\d+$/.test(version)) {
      process.exit(1);
    }
    process.stdout.write(version);
  ' "$manifest" "$package"
}

ai_commands_match() {
  local root="$1"
  local codex_version="$2"
  local claude_version="$3"
  local codex_output
  local claude_output

  [[ -x "$root/node_modules/.bin/codex" &&
    -x "$root/node_modules/.bin/claude" ]] || return 1
  codex_output="$(
    CODEX_HOME="$(dev_server_home)/.codex-work" \
      "$root/node_modules/.bin/codex" --version
  )" || return 1
  claude_output="$(
    CLAUDE_CONFIG_DIR="$(dev_server_home)/.claude-work" \
      "$root/node_modules/.bin/claude" --version
  )" || return 1
  [[ "$codex_output" == "codex-cli $codex_version" &&
    "$claude_output" == "$claude_version (Claude Code)" ]]
}

ai_packages_current() {
  local assets
  local root
  local codex_version
  local claude_version

  assets="$(ai_assets_dir)"
  root="$(ai_install_root)"
  codex_version="$(ai_package_version "$assets/package.json" @openai/codex)" ||
    return 1
  claude_version="$(ai_package_version "$assets/package.json" @anthropic-ai/claude-code)" ||
    return 1

  [[ -f "$root/.installed-package-lock.json" &&
    ! -L "$root/.installed-package-lock.json" ]] || return 1
  [[ -f "$root/.installed-package.json" &&
    ! -L "$root/.installed-package.json" ]] || return 1
  cmp -s "$assets/package.json" "$root/.installed-package.json" || return 1
  cmp -s "$assets/package-lock.json" \
    "$root/.installed-package-lock.json" || return 1
  [[ "$(ai_package_version "$root/node_modules/@openai/codex/package.json" \
    @openai/codex 2>/dev/null || true)" == "$codex_version" ]] || return 1
  [[ "$(ai_package_version \
    "$root/node_modules/@anthropic-ai/claude-code/package.json" \
    @anthropic-ai/claude-code 2>/dev/null || true)" == "$claude_version" ]] || return 1
  ai_commands_match "$root" "$codex_version" "$claude_version"
}

ai_install_packages() {
  local assets
  local root
  local status
  local manifest_status
  local lock_status
  local codex_version
  local claude_version

  assets="$(ai_assets_dir)"
  root="$(ai_install_root)"

  atomic_install_file "$assets/package.json" "$root/package.json" 0644 || return 1
  # atomic_install_file publishes this status through the shared contract.
  # shellcheck disable=SC2154
  manifest_status="$dev_server_install_status"
  atomic_install_file "$assets/package-lock.json" \
    "$root/package-lock.json" 0644 || return 1
  lock_status="$dev_server_install_status"
  if ai_packages_current; then
    [[ "$manifest_status" == "UP TO DATE" ]] ||
      render_result "$manifest_status" "AI package manifest"
    [[ "$lock_status" == "UP TO DATE" ]] ||
      render_result "$lock_status" "AI package lock"
    return 0
  fi

  if [[ -e "$root/.installed-package.json" ||
    -e "$root/.installed-package-lock.json" || -d "$root/node_modules" ]]; then
    status=UPDATED
  else
    status=INSTALLED
  fi
  (cd "$root" && npm ci --omit=dev --no-audit --no-fund \
    --strict-allow-scripts --ignore-scripts=false \
    --dangerously-allow-all-scripts=false) ||
    return 1
  codex_version="$(ai_package_version "$assets/package.json" @openai/codex)" ||
    die "invalid Codex package version"
  claude_version="$(ai_package_version \
    "$assets/package.json" @anthropic-ai/claude-code)" ||
    die "invalid Claude package version"
  ai_commands_match "$root" "$codex_version" "$claude_version" ||
    die "installed AI commands do not match their declared versions"
  atomic_install_file "$assets/package.json" \
    "$root/.installed-package.json" 0600 || return 1
  atomic_install_file "$assets/package-lock.json" \
    "$root/.installed-package-lock.json" 0600 || return 1

  ai_packages_current || die "installed AI package tree does not match its lock"
  render_result "$status" "AI tools" \
    "codex@$codex_version claude@$claude_version"
}

ai_install_profiles() {
  local home
  local profile

  home="$(dev_server_home)"
  profile="$(dev_server_assets_dir)/routers/ai-profile"
  [[ -f "$profile" && ! -L "$profile" ]] ||
    die "missing AI profile wrapper: $profile"

  install_managed_file "$profile" \
    "$home/bin/codex-work" 0755 shell.config || return 1
  install_managed_file "$profile" \
    "$home/bin/codex-work2" 0755 shell.config || return 1
  install_managed_file "$profile" \
    "$home/bin/claude-work" 0755 shell.config || return 1
}

ai_install() {
  ai_require_runtime
  ai_validate_inputs
  ai_install_dirs || return 1
  ai_install_packages || return 1
  ai_install_profiles || return 1
}
