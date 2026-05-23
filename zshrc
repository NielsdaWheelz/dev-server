# Managed by dev-server bootstrap.

if [ -z "${ZSH_VERSION:-}" ]; then
  echo "This file is for zsh. Run 'exec zsh' or open a new SSH session instead."
  return 0 2>/dev/null || exit 0
fi

export EDITOR="${EDITOR:-vim}"
export PAGER="${PAGER:-less}"

case ":$PATH:" in
  *":$HOME/bin:"*) ;;
  *) export PATH="$HOME/bin:$PATH" ;;
esac

HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=50000

setopt auto_cd
setopt auto_pushd
setopt extended_history
setopt hist_ignore_all_dups
setopt hist_reduce_blanks
setopt inc_append_history
setopt interactive_comments
setopt prompt_subst
setopt share_history

autoload -Uz colors
colors

if [[ -x /usr/bin/dircolors ]]; then
  eval "$(/usr/bin/dircolors -b)"
  zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
fi

autoload -Uz compinit
compinit

zstyle ':completion:*' menu no
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' squeeze-slashes true

if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh)"
fi

if [[ -o interactive && -t 0 && -t 1 ]]; then
  if [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  fi

  if [[ -r /usr/share/doc/fzf/examples/completion.zsh ]]; then
    source /usr/share/doc/fzf/examples/completion.zsh
  fi

  if [[ -r "$HOME/.zsh/fzf-tab/fzf-tab.zsh" ]]; then
    source "$HOME/.zsh/fzf-tab/fzf-tab.zsh"
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color=always $realpath 2>/dev/null'
    zstyle ':fzf-tab:*' switch-group '<' '>'
  fi

  if [[ -r /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=8'
  fi
fi

if [[ -r "$HOME/.bash_aliases" ]]; then
  source "$HOME/.bash_aliases"
fi

_dev_server_git_branch() {
  local branch
  branch="$(git branch --show-current 2>/dev/null)" || return
  [[ -n "$branch" ]] && printf ' (%s)' "$branch"
}

PROMPT='%F{green}%n@%m%f:%F{blue}%~%f%F{yellow}$(_dev_server_git_branch)%f %# '

# zsh-syntax-highlighting should be sourced after widgets and completions.
if [[ -o interactive && -t 0 && -t 1 && -r /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
