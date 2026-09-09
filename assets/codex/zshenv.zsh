# Managed Devbox command routing, including non-interactive SSH shells.
# zsh's unique path array removes later duplicates without preserving a stale
# raw-binary-first ordering inherited from the parent process.
typeset -U path
path=("$HOME/bin" "$HOME/.local/bin" "$HOME/.local/share/mise/shims" /usr/local/bin $path)
export PATH
