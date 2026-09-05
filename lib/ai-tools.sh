#!/usr/bin/env bash

ai_require_codex_runtime() {
  local npm_version

  require_cmd node
  require_cmd npm
  node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 24 ? 0 : 1)' ||
    die "Codex requires Node.js 24 or newer"
  npm_version="$(npm --version)" || die "could not read the npm version"
  node - "$npm_version" <<'NODE' || die "Codex requires npm 11.17.0 or newer"
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
  local profile

  profile="$(dev_server_assets_dir)/routers/ai-profile"
  [[ -f "$profile" && ! -L "$profile" ]] ||
    die "invalid AI profile wrapper: $profile"
}

ai_install_dirs() {
  local home

  home="$(dev_server_home)"
  ensure_directory "$home/bin" 0755 || return 1
  ensure_directory "$home/.local" 0755 || return 1
  ensure_directory "$home/.local/bin" 0755 || return 1
  ensure_directory "$home/.local/share" 0755 || return 1
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
  local installer

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
  HOME="$home" bash "$installer" latest ||
    die "Claude native installation failed"
)

ai_install_claude() {
  local before
  local binary
  local home
  local status
  local version

  home="$(dev_server_home)"
  binary="$(ai_claude_binary)"
  if before="$(ai_claude_native_version)"; then
    HOME="$home" "$binary" install latest ||
      die "Claude native latest-channel reconciliation failed"
    version="$(ai_claude_native_version)" ||
      die "Claude native reconciliation produced an invalid installation"
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
  render_result "$status" "AI tool" "claude@$version"
}

ai_install_packages() {
  ai_install_codex || return 1
  ai_install_claude || return 1
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
  ai_require_codex_runtime
  ai_validate_inputs
  ai_install_dirs || return 1
  ai_install_packages || return 1
  ai_install_profiles || return 1
}
