#!/usr/bin/env bash

dotfiles_asset() {
  printf '%s/dotfiles/%s\n' "$(dev_server_assets_dir)" "$1"
}

dotfiles_validate_declared_inputs() {
  local asset
  local -a assets=(
    gitconfig
    gitignore_global
    p10k.zsh
    tmux.conf
    zsh_helpers
    zshenv
    zshrc
  )

  for asset in "${assets[@]}"; do
    asset="$(dotfiles_asset "$asset")"
    [[ -f "$asset" && ! -L "$asset" ]] || die "invalid dotfile asset: $asset"
  done
}

dotfiles_validate_inputs() {
  dotfiles_validate_declared_inputs
  require_cmd git python3
  dotfiles_validate_local_state
}

dotfiles_validate_git_state() {
  local url="$1"
  local dest="$2"
  local slug plugin_root path name target

  slug="$(basename "$dest")"
  plugin_root="$(dev_server_home)/.local/share/dev-server/git-plugins/$slug"
  if [[ -e "$plugin_root" || -L "$plugin_root" ]]; then
    [[ -d "$plugin_root" && ! -L "$plugin_root" ]] ||
      die "Git plugin generation root is invalid: $plugin_root"
    while IFS= read -r -d '' path; do
      name="$(basename "$path")"
      if [[ "$name" == .git-stage.?????? ]]; then
        [[ -d "$path" && ! -L "$path" ]] ||
          die "interrupted Git plugin stage is invalid: $path"
      elif [[ "$name" =~ ^[0-9a-f]{40}$ ]]; then
        dotfiles_git_repo_exact "$url" "$name" "$path" ||
          die "Git plugin generation is invalid: $path"
      else
        die "unowned Git plugin generation remains: $path"
      fi
    done < <(find "$plugin_root" -mindepth 1 -maxdepth 1 -print0)
  fi

  [[ -e "$dest" || -L "$dest" ]] || return 0
  [[ -L "$dest" ]] ||
    die "legacy in-place Git plugin remains; complete the hard-cut runbook: $dest"
  target="$(readlink "$dest")"
  case "$target" in
  "$plugin_root"/[0-9a-f][0-9a-f]*) ;;
  *) die "Git plugin link is outside its managed generations: $dest" ;;
  esac
  name="$(basename "$target")"
  [[ "$name" =~ ^[0-9a-f]{40}$ ]] || die "Git plugin link is invalid: $dest"
  dotfiles_git_repo_exact "$url" "$name" "$target" ||
    die "Git plugin link target is invalid: $dest"
}

dotfiles_validate_local_state() {
  local home

  require_cmd find git
  home="$(dev_server_home)"
  dotfiles_validate_git_state \
    https://github.com/Aloxaf/fzf-tab "$home/.zsh/fzf-tab"
  dotfiles_validate_git_state \
    https://github.com/romkatv/powerlevel10k.git "$home/.zsh/powerlevel10k"
  dotfiles_validate_git_state \
    https://github.com/tmux-plugins/tpm "$home/.tmux/plugins/tpm"
  dotfiles_validate_git_state \
    https://github.com/tmux-plugins/tmux-resurrect "$home/.tmux/plugins/tmux-resurrect"
  dotfiles_validate_git_state \
    https://github.com/tmux-plugins/tmux-continuum "$home/.tmux/plugins/tmux-continuum"
}

dotfiles_install_dirs() {
  local home

  home="$(dev_server_home)"
  ensure_directory "$home/bin" 0755 || return 1
  ensure_directory "$home/.local" 0755 || return 1
  ensure_directory "$home/.local/bin" 0755 || return 1
  ensure_directory "$home/.local/share" 0755 || return 1
  ensure_directory "$home/.local/share/dev-server" 0755 || return 1
  ensure_directory "$home/.local/share/dev-server/git-plugins" 0755 || return 1
  ensure_directory "$home/.config" 0755 || return 1
  ensure_directory "$home/.ssh" 0700 || return 1
  ensure_directory "$home/.zsh" 0755 || return 1
  ensure_directory "$home/.tmux" 0755 || return 1
  ensure_directory "$home/.tmux/plugins" 0755 || return 1
  ensure_directory "$home/src" 0755 || return 1
  ensure_directory "$home/src/work" 0755 || return 1
  ensure_directory "$home/src/personal" 0755 || return 1
  ensure_directory "$home/.ai-images" 0755 || return 1
}

dotfiles_install_files() {
  local home
  local status

  home="$(dev_server_home)"
  install_managed_file "$(dotfiles_asset zshenv)" \
    "$home/.zshenv" 0644 shell.config || return 1
  install_managed_file "$(dotfiles_asset zshrc)" \
    "$home/.zshrc" 0644 shell.config || return 1
  install_managed_file "$(dotfiles_asset zsh_helpers)" \
    "$home/.zsh_helpers" 0644 shell.config || return 1
  install_managed_file "$(dotfiles_asset p10k.zsh)" \
    "$home/.p10k.zsh" 0644 shell.config || return 1
  install_managed_file "$(dotfiles_asset tmux.conf)" \
    "$home/.tmux.conf" 0644 tmux.config || return 1
  install_managed_file "$(dotfiles_asset gitignore_global)" \
    "$home/.gitignore_global" 0644 shell.config || return 1

  atomic_install_file "$(dotfiles_asset gitconfig)" \
    "$home/.gitconfig" 0644 || return 1
  # Published by the shared atomic installer.
  # shellcheck disable=SC2154
  status="$dev_server_install_status"
  case "$status" in
  INSTALLED | UPDATED) render_result "$status" "$home/.gitconfig" ;;
  UP\ TO\ DATE) ;;
  *) die "invalid install result for $home/.gitconfig: $status" ;;
  esac
}

dotfiles_git_repo_exact() {
  local url="$1"
  local commit="$2"
  local repo="$3"
  local worktree

  [[ -d "$repo" && ! -L "$repo" && -d "$repo/.git" && ! -L "$repo/.git" ]] ||
    return 1
  [[ "$(git -C "$repo" remote get-url origin 2>/dev/null)" == "$url" ]] ||
    return 1
  [[ "$(git -C "$repo" rev-parse --verify HEAD 2>/dev/null)" == "$commit" ]] ||
    return 1
  worktree="$(git -C "$repo" status --porcelain --untracked-files=all 2>/dev/null)" ||
    return 1
  [[ -z "$worktree" ]]
}

dotfiles_prepare_git_generation() (
  local url="$1"
  local commit="$2"
  local generation="$3"
  local stage=''

  cleanup_git_stage() {
    [[ -z "$stage" ]] || rm -Rf -- "$stage"
  }
  trap cleanup_git_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  stage="$(mktemp -d "$(dirname "$generation")/.git-stage.XXXXXX")" || return 1
  git init --quiet "$stage" || return 1
  git -C "$stage" remote add origin "$url" || return 1
  git -C "$stage" fetch --quiet --depth=1 origin "$commit" || return 1
  git -C "$stage" checkout --quiet --detach FETCH_HEAD || return 1
  dotfiles_git_repo_exact "$url" "$commit" "$stage" || return 1
  mv "$stage" "$generation" || return 1
  stage=''
)

dotfiles_atomic_symlink() (
  local target="$1"
  local link="$2"
  local temporary=''

  cleanup_link_stage() {
    [[ -z "$temporary" ]] || rm -f -- "$temporary"
  }
  trap cleanup_link_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  temporary="$(mktemp "$(dirname "$link")/.$(basename "$link").link.XXXXXX")" ||
    return 1
  rm -f -- "$temporary" || return 1
  ln -s "$target" "$temporary" || return 1
  python3 - "$temporary" "$link" <<'PY' || return 1
import os
import sys

os.replace(sys.argv[1], sys.argv[2])
PY
  temporary=''
  [[ -L "$link" && "$(readlink "$link")" == "$target" ]]
)

dotfiles_prune_git_generations() {
  local url="$1"
  local desired="$2"
  local root="$3"
  local path commit

  while IFS= read -r -d '' path; do
    [[ "$path" == "$desired" ]] && continue
    commit="$(basename "$path")"
    [[ "$commit" =~ ^[0-9a-f]{40}$ ]] ||
      die "unowned Git plugin generation remains: $path"
    dotfiles_git_repo_exact "$url" "$commit" "$path" ||
      die "invalid Git plugin generation remains: $path"
    rm -Rf -- "$path" || die "could not prune Git plugin generation: $path"
  done < <(find "$root" -mindepth 1 -maxdepth 1 -print0)
}

dotfiles_cleanup_git_stages() {
  local root="$1"
  local path

  while IFS= read -r -d '' path; do
    [[ -d "$path" && ! -L "$path" ]] ||
      die "invalid interrupted Git plugin stage: $path"
    rm -Rf -- "$path" || die "could not remove interrupted Git plugin stage: $path"
  done < <(find "$root" -mindepth 1 -maxdepth 1 \
    -name '.git-stage.??????' -print0)
}

dotfiles_install_git_repo() {
  local url="$1"
  local commit="$2"
  local dest="$3"
  local change="$4"
  local generation plugin_root slug status head existing_target

  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || die "invalid Git plugin commit: $commit"
  slug="$(basename "$dest")"
  [[ "$slug" =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid Git plugin name: $slug"
  plugin_root="$(dev_server_home)/.local/share/dev-server/git-plugins/$slug"
  ensure_directory "$plugin_root" 0755 >/dev/null || return 1
  dotfiles_cleanup_git_stages "$plugin_root"
  generation="$plugin_root/$commit"

  if [[ -e "$dest" && ! -d "$dest" && ! -L "$dest" ]]; then
    die "Git plugin path is not a regular directory: $dest"
  fi
  if [[ -L "$dest" ]]; then
    existing_target="$(readlink "$dest")"
    case "$existing_target" in
    "$plugin_root"/[0-9a-f][0-9a-f]*) ;;
    *) die "Git plugin link is outside its managed generations: $dest" ;;
    esac
    head="$(basename "$existing_target")"
    [[ "$head" =~ ^[0-9a-f]{40}$ ]] || die "Git plugin link is invalid: $dest"
    dotfiles_git_repo_exact "$url" "$head" "$existing_target" ||
      die "Git plugin link target is invalid: $dest"
    if [[ "$head" == "$commit" ]]; then
      dotfiles_prune_git_generations "$url" "$generation" "$plugin_root"
      return 0
    fi
    status=UPDATED
  elif [[ -e "$dest" ]]; then
    die "legacy in-place Git plugin remains; complete the hard-cut runbook: $dest"
  else
    status=INSTALLED
  fi

  if [[ -e "$generation" || -L "$generation" ]]; then
    dotfiles_git_repo_exact "$url" "$commit" "$generation" ||
      die "immutable Git plugin generation is invalid: $generation"
  else
    dotfiles_prepare_git_generation "$url" "$commit" "$generation" ||
      die "could not prepare the declared Git plugin commit: $dest"
  fi
  dotfiles_atomic_symlink "$generation" "$dest" ||
    die "could not activate the declared Git plugin generation: $dest"
  dotfiles_git_repo_exact "$url" "$commit" "$generation" ||
    die "activated Git plugin generation is invalid: $dest"
  dotfiles_prune_git_generations "$url" "$generation" "$plugin_root"
  record_change "$change"
  render_result "$status" "Git plugin" "$(basename "$dest")@$commit"
}

dotfiles_install_shell_repos() {
  local home

  home="$(dev_server_home)"
  dotfiles_install_git_repo \
    https://github.com/Aloxaf/fzf-tab \
    24105b15714bfec37989ed5c5b6e60f572253019 \
    "$home/.zsh/fzf-tab" shell.config || return 1
  dotfiles_install_git_repo \
    https://github.com/romkatv/powerlevel10k.git \
    3308262dfbd743b6e1d3956a2b5572f7a049d692 \
    "$home/.zsh/powerlevel10k" shell.config || return 1
}

dotfiles_install_tmux_repos() {
  local home

  home="$(dev_server_home)"
  dotfiles_install_git_repo \
    https://github.com/tmux-plugins/tpm \
    e261deb1b47614eed3400089ce7197dc68acc4eb \
    "$home/.tmux/plugins/tpm" tmux.config || return 1
  dotfiles_install_git_repo \
    https://github.com/tmux-plugins/tmux-resurrect \
    cff343cf9e81983d3da0c8562b01616f12e8d548 \
    "$home/.tmux/plugins/tmux-resurrect" tmux.config || return 1
  dotfiles_install_git_repo \
    https://github.com/tmux-plugins/tmux-continuum \
    0698e8f4b17d6454c71bf5212895ec055c578da0 \
    "$home/.tmux/plugins/tmux-continuum" tmux.config || return 1
}

dotfiles_reload_tmux_if_changed() {
  local desired_sha observed_sha status

  command -v tmux >/dev/null 2>&1 || return 0
  if tmux list-sessions >/dev/null 2>&1; then
    status=0
  else
    status=$?
  fi
  ((status == 0)) || {
    ((status == 1)) && return 0
    die 'could not observe tmux session state'
  }

  desired_sha="$(dev_server_sha256 "$(dev_server_home)/.tmux.conf")"
  if observed_sha="$(tmux show-options -gv @dev-server-config-sha 2>/dev/null)"; then
    [[ "$observed_sha" =~ ^[0-9a-f]{64}$ ]] ||
      die 'running tmux config identity is invalid'
    [[ "$observed_sha" == "$desired_sha" ]] && return 0
  fi

  tmux source-file "$(dev_server_home)/.tmux.conf" ||
    die 'could not reload tmux configuration'
  tmux set-option -gq @dev-server-config-sha "$desired_sha" ||
    die 'could not record the running tmux config identity'
  render_result RELOADED tmux
}

dotfiles_install() {
  dotfiles_validate_inputs
  dotfiles_install_dirs || return 1
  dotfiles_install_files || return 1
  dotfiles_install_tmux_repos || return 1
  dotfiles_reload_tmux_if_changed || return 1
  dotfiles_install_shell_repos || return 1
}
