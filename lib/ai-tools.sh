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
names = ["@anthropic-ai/claude-code"]
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
  ensure_directory "$home/.local/bin" 0755 || return 1
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

ai_codex_binary() {
  printf '%s/.local/bin/codex\n' "$(dev_server_home)"
}

ai_codex_manifest() {
  printf '%s/.local/lib/node_modules/@openai/codex/package.json\n' \
    "$(dev_server_home)"
}

ai_codex_candidate() {
  local value

  value="$(npm view @openai/codex dist-tags.latest --json)" ||
    die "could not resolve the current stable Codex release"
  node -e '
    const value = JSON.parse(process.argv[1]);
    if (typeof value !== "string" || !/^\d+\.\d+\.\d+$/.test(value)) {
      process.exit(1);
    }
    process.stdout.write(value);
  ' "$value" || die "npm returned an invalid stable Codex release"
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

  candidate="$(ai_codex_candidate)"
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
    die "installed Codex does not match npm's stable candidate"
  render_result "$status" "AI tool" "codex@$candidate"
}

ai_claude_command_matches() {
  local root="$1"
  local claude_version="$2"
  local claude_output

  [[ -x "$root/node_modules/.bin/claude" ]] || return 1
  claude_output="$(
    CLAUDE_CONFIG_DIR="$(dev_server_home)/.claude-work" \
      "$root/node_modules/.bin/claude" --version
  )" || return 1
  [[ "$claude_output" == "$claude_version (Claude Code)" ]]
}

ai_claude_packages_current() {
  local assets
  local root
  local claude_version

  assets="$(ai_assets_dir)"
  root="$(ai_install_root)"
  claude_version="$(ai_package_version "$assets/package.json" @anthropic-ai/claude-code)" ||
    return 1

  [[ -f "$root/.installed-package-lock.json" &&
    ! -L "$root/.installed-package-lock.json" ]] || return 1
  [[ -f "$root/.installed-package.json" &&
    ! -L "$root/.installed-package.json" ]] || return 1
  cmp -s "$assets/package.json" "$root/.installed-package.json" || return 1
  cmp -s "$assets/package-lock.json" \
    "$root/.installed-package-lock.json" || return 1
  [[ ! -e "$root/node_modules/@openai/codex" &&
    ! -L "$root/node_modules/@openai/codex" &&
    ! -e "$root/node_modules/.bin/codex" &&
    ! -L "$root/node_modules/.bin/codex" ]] || return 1
  [[ "$(ai_package_version \
    "$root/node_modules/@anthropic-ai/claude-code/package.json" \
    @anthropic-ai/claude-code 2>/dev/null || true)" == "$claude_version" ]] || return 1
  ai_claude_command_matches "$root" "$claude_version"
}

ai_install_locked_claude() {
  local assets
  local root
  local status
  local manifest_status
  local lock_status
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
  if ai_claude_packages_current; then
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
  claude_version="$(ai_package_version \
    "$assets/package.json" @anthropic-ai/claude-code)" ||
    die "invalid Claude package version"
  ai_claude_command_matches "$root" "$claude_version" ||
    die "installed Claude command does not match its declared version"
  atomic_install_file "$assets/package.json" \
    "$root/.installed-package.json" 0600 || return 1
  atomic_install_file "$assets/package-lock.json" \
    "$root/.installed-package-lock.json" 0600 || return 1

  ai_claude_packages_current ||
    die "installed Claude package tree does not match its lock"
  render_result "$status" "AI tool" "claude@$claude_version"
}

ai_install_packages() {
  ai_install_codex || return 1
  ai_install_locked_claude || return 1
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
