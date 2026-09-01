#!/usr/bin/env bash
# Globals in this fixture are consumed by sourced production functions.
# shellcheck disable=SC2034
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-dotfiles.XXXXXX")"
trap 'rm -rf "$fixture"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

pass() {
  tests_run=$((tests_run + 1))
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "$actual" == "$expected" ]] ||
    fail "$label: expected [$expected], got [$actual]"
}

test_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

file_inode() {
  stat -c '%i' "$1" 2>/dev/null || stat -f '%i' "$1"
}

reset_results() {
  dev_server_changes='|'
  dev_server_change_count=0
  dev_server_result_mutations=0
  dev_server_result_activations=0
  dev_server_result_deferrals=0
  dev_server_result_actions=0
  dev_server_result_errors=0
  dev_server_install_status='UP TO DATE'
}

test_home="$fixture/home"
test_assets="$fixture/assets"
install -d -m 0755 "$test_home"
cp -R "$repo_dir/assets" "$test_assets"

dev_server_home_dir="$test_home"
dev_server_assets_root="$test_assets"
# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=lib/dotfiles.sh
source "$repo_dir/lib/dotfiles.sh"

tmux_running=1
tmux_calls="$fixture/tmux-calls"
tmux_config_sha=''
tmux() {
  case "$1" in
  list-sessions)
    [[ "$tmux_running" == 1 ]]
    ;;
  source-file)
    printf '%s\n' "$2" >>"$tmux_calls"
    ;;
  show-options)
    [[ -n "$tmux_config_sha" ]] || return 1
    printf '%s\n' "$tmux_config_sha"
    ;;
  set-option)
    tmux_config_sha="$4"
    ;;
  *) fail "unexpected tmux call: $*" ;;
  esac
}

test_atomic_files_and_tmux_activation() {
  local inode

  reset_results
  dotfiles_install_dirs >/dev/null
  dotfiles_install_files >/dev/null
  has_change shell.config || fail 'fresh shell files did not record shell.config'
  has_change tmux.config || fail 'fresh tmux file did not record tmux.config'
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq 1 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'fresh tmux activation count'
  cmp -s "$test_assets/dotfiles/tmux.conf" "$test_home/.tmux.conf" ||
    fail 'tmux configuration bytes differ'
  cmp -s "$test_assets/dotfiles/gitconfig" "$test_home/.gitconfig" ||
    fail 'global Git configuration bytes differ'
  assert_eq 644 "$(test_mode "$test_home/.tmux.conf")" 'tmux mode'
  assert_eq 700 "$(test_mode "$test_home/.ssh")" 'SSH directory mode'

  inode="$(file_inode "$test_home/.tmux.conf")"
  reset_results
  dotfiles_install_dirs >/dev/null
  dotfiles_install_files >/dev/null
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq "$inode" "$(file_inode "$test_home/.tmux.conf")" \
    'unchanged tmux file inode'
  assert_eq 1 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'second-apply tmux activation count'
  ((dev_server_result_mutations == 0)) ||
    fail 'second file apply reported a durable mutation'

  printf '\n# shell-only change\n' >>"$test_assets/dotfiles/zshrc"
  reset_results
  dotfiles_install_files >/dev/null
  has_change shell.config || fail 'shell update did not record shell.config'
  if has_change tmux.config; then
    fail 'shell-only update recorded tmux.config'
  fi
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq 1 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'unrelated-change tmux activation count'

  printf '\n# tmux change\n' >>"$test_assets/dotfiles/tmux.conf"
  reset_results
  dotfiles_install_files >/dev/null
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq 2 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'changed tmux activation count'

  chmod 0600 "$test_home/.tmux.conf"
  reset_results
  dotfiles_install_files >/dev/null
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq 2 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'tmux mode-repair activation count'

  tmux_config_sha=''
  reset_results
  dotfiles_install_files >/dev/null
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq 3 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'interrupted tmux activation retry count'

  tmux_running=0
  printf '\n# next server reads this\n' >>"$test_assets/dotfiles/tmux.conf"
  reset_results
  dotfiles_install_files >/dev/null
  dotfiles_reload_tmux_if_changed >/dev/null
  assert_eq 3 "$(wc -l <"$tmux_calls" | tr -d ' ')" \
    'inactive-server tmux activation count'
  pass
}

test_protected_target_rejected() {
  rm "$test_home/.tmux.conf"
  ln -s "$fixture/not-managed" "$test_home/.tmux.conf"
  if (dotfiles_install_files) >/dev/null 2>&1; then
    fail 'managed dotfile accepted a symlink target'
  fi
  rm "$test_home/.tmux.conf"
  install -m 0644 "$test_assets/dotfiles/tmux.conf" "$test_home/.tmux.conf"
  pass
}

test_pinned_git_repositories() {
  local source_repo="$fixture/source-plugin"
  local installed_repo="$fixture/installed-plugin"
  local first_commit
  local second_commit

  git init --quiet "$source_repo"
  git -C "$source_repo" config user.email test@example.invalid
  git -C "$source_repo" config user.name 'dev-server test'
  printf 'first\n' >"$source_repo/plugin.zsh"
  git -C "$source_repo" add plugin.zsh
  git -C "$source_repo" commit --quiet -m first
  first_commit="$(git -C "$source_repo" rev-parse HEAD)"

  reset_results
  dotfiles_install_git_repo "$source_repo" "$first_commit" \
    "$installed_repo" shell.config >/dev/null
  assert_eq "$first_commit" "$(git -C "$installed_repo" rev-parse HEAD)" \
    'fresh plugin commit'
  has_change shell.config || fail 'fresh plugin did not record shell.config'

  reset_results
  dotfiles_install_git_repo "$source_repo" "$first_commit" \
    "$installed_repo" shell.config >/dev/null
  if has_change shell.config; then
    fail 'unchanged plugin recorded a change'
  fi
  ((dev_server_result_mutations == 0)) ||
    fail 'unchanged plugin reported a mutation'

  printf 'second\n' >"$source_repo/plugin.zsh"
  git -C "$source_repo" commit --quiet -am second
  second_commit="$(git -C "$source_repo" rev-parse HEAD)"
  reset_results
  dotfiles_install_git_repo "$source_repo" "$second_commit" \
    "$installed_repo" shell.config >/dev/null
  assert_eq "$second_commit" "$(git -C "$installed_repo" rev-parse HEAD)" \
    'updated plugin commit'
  has_change shell.config || fail 'plugin update did not record shell.config'

  printf 'local edit\n' >>"$installed_repo/plugin.zsh"
  if (dotfiles_install_git_repo "$source_repo" "$second_commit" \
    "$installed_repo" shell.config) >/dev/null 2>&1; then
    fail 'plugin reconciliation overwrote a local edit'
  fi
  pass
}

test_interrupted_git_checkout_retries_cleanly() (
  local source_repo="$fixture/interrupted-source-plugin"
  local installed_repo="$test_home/.zsh/interrupted-plugin"
  local commit fail_once="$fixture/interrupted-checkout"

  git init --quiet "$source_repo"
  git -C "$source_repo" config user.email test@example.invalid
  git -C "$source_repo" config user.name 'dev-server test'
  printf 'plugin\n' >"$source_repo/plugin.zsh"
  git -C "$source_repo" add plugin.zsh
  git -C "$source_repo" commit --quiet -m plugin
  commit="$(git -C "$source_repo" rev-parse HEAD)"
  dotfiles_install_dirs >/dev/null

  git() {
    if [[ "$*" == *' checkout --quiet --detach FETCH_HEAD' && ! -e "$fail_once" ]]; then
      : >"$fail_once"
      return 73
    fi
    command git "$@"
  }

  if (dotfiles_install_git_repo "$source_repo" "$commit" \
    "$installed_repo" shell.config) >/dev/null 2>&1; then
    fail 'interrupted Git checkout unexpectedly succeeded'
  fi
  [[ ! -e "$installed_repo" && ! -L "$installed_repo" ]] ||
    fail 'interrupted Git checkout published a plugin'
  assert_eq 0 "$(find "$test_home/.local/share/dev-server/git-plugins/interrupted-plugin" \
    -mindepth 1 -maxdepth 1 -name '.git-stage.*' | wc -l | tr -d ' ')" \
    'interrupted Git stage residue count'

  dotfiles_install_git_repo "$source_repo" "$commit" \
    "$installed_repo" shell.config >/dev/null
  [[ -L "$installed_repo" ]] || fail 'Git retry did not publish an immutable link'
  assert_eq "$commit" "$(git -C "$installed_repo" rev-parse HEAD)" \
    'Git retry commit'
)

test_git_config_is_fully_owned() {
  local inode

  export HOME="$test_home"
  printf '%s\n' \
    '[user]' \
    '  name = Local Identity' \
    '[init]' \
    '  defaultBranch = unmanaged' >"$test_home/.gitconfig.local"
  assert_eq main "$(git -C "$test_home" config init.defaultBranch)" \
    'Git default branch'
  assert_eq 'Local Identity' "$(git -C "$test_home" config user.name)" \
    'Git personal include identity'
  inode="$(file_inode "$test_home/.gitconfig")"
  reset_results
  dotfiles_install_files >/dev/null
  assert_eq "$inode" "$(file_inode "$test_home/.gitconfig")" \
    'unchanged Git config inode'
  ((dev_server_result_mutations == 0)) ||
    fail 'unchanged Git configuration reported a mutation'
  grep -Fq 'path = ~/.gitconfig.local' "$test_home/.gitconfig" ||
    fail 'fully owned Git config does not expose its personal include'
  pass
}

test_static_reduction_contract() {
  local source="$repo_dir/lib/dotfiles.sh"

  if grep -Eq 'doctor|xfce|ghostty|gammastep|clipman|systemctl' "$source"; then
    fail 'host policy or diagnostics remain in dotfiles.sh'
  fi
  if grep -Eq 'git (pull|clone)|kill-server|restart-server' "$source"; then
    fail 'mutable Git or destructive tmux behavior remains'
  fi
  assert_eq 5 "$(grep -Eoc '^[[:space:]]+[0-9a-f]{40} \\$' "$source")" \
    'pinned Git plugin count'
  grep -F '@dev-server-config-sha' "$source" >/dev/null ||
    fail 'tmux reload is not gated by its live config identity'
  if grep -Eq 'git config --global|insteadOf' "$source"; then
    fail 'partial or legacy global Git configuration remains'
  fi
  assert_eq 1 "$(grep -Fhl 'ai-tools/node_modules/.bin' \
    "$repo_dir/assets/dotfiles/zshenv" \
    "$repo_dir/assets/dotfiles/zshrc" \
    "$repo_dir/assets/dotfiles/zsh_helpers" | wc -l | tr -d ' ')" \
    'AI PATH owner count'
  pass
}

test_invalid_input_is_read_only() {
  local invalid_assets="$fixture/invalid-assets"
  local invalid_home="$fixture/invalid-home"

  cp -R "$repo_dir/assets" "$invalid_assets"
  install -d -m 0755 "$invalid_home"
  rm "$invalid_assets/dotfiles/zshrc"
  if (
    dev_server_home_dir="$invalid_home"
    dev_server_assets_root="$invalid_assets"
    dotfiles_install
  ) >/dev/null 2>&1; then
    fail 'dotfiles accepted an incomplete desired state'
  fi
  assert_eq 0 "$(find "$invalid_home" -mindepth 1 | wc -l | tr -d ' ')" \
    'invalid dotfile input mutation count'
  pass
}

tests_run=0
test_atomic_files_and_tmux_activation
test_protected_target_rejected
test_pinned_git_repositories
test_interrupted_git_checkout_retries_cleanly
pass
test_git_config_is_fully_owned
test_static_reduction_contract
test_invalid_input_is_read_only

printf 'PASS: %d dotfile test groups\n' "$tests_run"
