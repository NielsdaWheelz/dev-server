#!/usr/bin/env bash

dotfiles_asset() {
  printf '%s/dotfiles/%s\n' "$(dev_server_assets_dir)" "$1"
}

dotfiles_install_file() {
  local source="$1"
  local dest="$2"
  local mode="${3:-0644}"

  [[ -f "$source" ]] || die "missing dotfile asset: $source"
  install -m "$mode" "$source" "$dest"
}

dotfiles_install_dirs() {
  local home

  home="$(dev_server_home)"
  install -d -m 0755 \
    "$home/bin" \
    "$home/.local/bin" \
    "$home/.npm" \
    "$home/.config" \
    "$home/.ssh" \
    "$home/.zsh" \
    "$home/.tmux/plugins" \
    "$home/src/work" \
    "$home/src/personal" \
    "$home/.ai-images"
}

dotfiles_install_git_repo() {
  local repo="$1"
  local dest="$2"

  require_cmd git
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" pull --ff-only
  else
    git clone "$repo" "$dest"
  fi
}

dotfiles_install_shell_repos() {
  local home

  home="$(dev_server_home)"
  dotfiles_install_git_repo https://github.com/Aloxaf/fzf-tab "$home/.zsh/fzf-tab"
  dotfiles_install_git_repo https://github.com/romkatv/powerlevel10k.git "$home/.zsh/powerlevel10k"
  dotfiles_install_git_repo https://github.com/tmux-plugins/tpm "$home/.tmux/plugins/tpm"
}

dotfiles_install_tmux_plugins() {
  local home

  home="$(dev_server_home)"
  if [[ -x "$home/.tmux/plugins/tpm/bin/install_plugins" ]]; then
    "$home/.tmux/plugins/tpm/bin/install_plugins"
  fi
}

dotfiles_configure_git() {
  local home

  home="$(dev_server_home)"
  require_cmd git
  git config --global core.excludesfile "$home/.gitignore_global"
  git config --global init.defaultBranch main
  git config --global core.pager delta
  git config --global interactive.diffFilter "delta --color-only"
  git config --global delta.navigate true
  git config --global delta.side-by-side false
  git config --global merge.conflictStyle zdiff3
  git config --global --unset-all url.git@github.com:.insteadOf || true
  git config --global --add url.git@github.com:.insteadOf https://github.com/
  git config --global --add url.git@github.com:.insteadOf gh:
}

dotfiles_install() {
  local home

  home="$(dev_server_home)"
  dotfiles_install_dirs
  dotfiles_install_file "$(dotfiles_asset zshrc)" "$home/.zshrc"
  dotfiles_install_file "$(dotfiles_asset zsh_helpers)" "$home/.zsh_helpers"
  dotfiles_install_file "$(dotfiles_asset p10k.zsh)" "$home/.p10k.zsh"
  dotfiles_install_file "$(dotfiles_asset tmux.conf)" "$home/.tmux.conf"
  dotfiles_install_file "$(dotfiles_asset gitignore_global)" "$home/.gitignore_global"
  dotfiles_install_shell_repos
  dotfiles_install_tmux_plugins
  dotfiles_configure_git
}

dotfiles_doctor() {
  local home
  local file
  local id
  local branch

  home="$(dev_server_home)"
  for file in .zshrc .zsh_helpers .p10k.zsh .tmux.conf .gitignore_global; do
    id="dotfiles.${file#.}"
    if [[ -f "$home/$file" ]]; then
      doctor_pass "$id" "$home/$file"
    else
      doctor_fail "$id" "missing $home/$file"
    fi
  done

  if command -v zsh >/dev/null 2>&1; then
    doctor_local_cmd dotfiles.zsh "zsh config parses" "zsh -n '$home/.zshrc' && zsh -n '$home/.zsh_helpers'"
  else
    doctor_fail dotfiles.zsh "zsh missing"
  fi

  branch="$(git config --global init.defaultBranch || true)"
  if [[ "$branch" == "main" ]]; then
    doctor_pass dotfiles.git "git defaults configured"
  else
    doctor_fail dotfiles.git "git init.defaultBranch is ${branch:-unset}, expected main"
  fi
}
