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

dotfiles_current_login_shell() {
  case "$(uname -s)" in
    Darwin)
      dscl . -read "/Users/$(id -un)" UserShell | awk '{print $2}'
      ;;
    Linux)
      getent passwd "$(id -un)" | cut -d: -f7
      ;;
  esac
}

dotfiles_configure_login_shell() {
  local current_shell
  local zsh_path

  require_cmd zsh
  zsh_path="$(command -v zsh)"
  current_shell="$(dotfiles_current_login_shell)"
  if [[ "$current_shell" != "$zsh_path" ]]; then
    log "setting login shell to $zsh_path"
    sudo chsh -s "$zsh_path" "$(id -un)"
  fi
}

dotfiles_configure_xfce_terminal() {
  local current_font
  local font_size

  [[ "$(uname -s)" == "Linux" ]] || return
  [[ "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]] || return
  command -v xfconf-query >/dev/null 2>&1 || return

  current_font="$(xfconf-query -c xfce4-terminal -p /font-name 2>/dev/null || printf 'Monospace 10')"
  font_size="${current_font##* }"
  [[ "$font_size" =~ ^[0-9]+$ ]] || font_size=10
  if xfconf-query -c xfce4-terminal -p /font-use-system >/dev/null 2>&1; then
    xfconf-query -c xfce4-terminal -p /font-use-system -s false
  else
    xfconf-query -c xfce4-terminal -p /font-use-system -n -t bool -s false
  fi
  if xfconf-query -c xfce4-terminal -p /font-name >/dev/null 2>&1; then
    xfconf-query -c xfce4-terminal -p /font-name -s "MesloLGS Nerd Font Mono $font_size"
  else
    xfconf-query -c xfce4-terminal -p /font-name -n -t string -s "MesloLGS Nerd Font Mono $font_size"
  fi
}

dotfiles_configure_ghostty() {
  local home
  local helpers_file

  [[ "$(uname -s)" == "Linux" ]] || return
  command -v ghostty >/dev/null 2>&1 || return

  home="$(dev_server_home)"
  install -d -m 0755 "$home/.config/ghostty"
  dotfiles_install_file "$(dotfiles_asset ghostty.config)" "$home/.config/ghostty/config.ghostty"

  if [[ "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]]; then
    install -d -m 0755 "$home/.local/share/xfce4/helpers" "$home/.config/xfce4"
    dotfiles_install_file \
      "$(dotfiles_asset ghostty-xfce-helper.desktop)" \
      "$home/.local/share/xfce4/helpers/ghostty.desktop"
    helpers_file="$home/.config/xfce4/helpers.rc"
    git config --file "$helpers_file" Helpers.TerminalEmulator ghostty
  fi

  systemctl --user enable --now app-com.mitchellh.ghostty.service
}

dotfiles_configure_xfce_theme() {
  [[ "$(uname -s)" == "Linux" ]] || return
  [[ "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]] || return
  command -v xfconf-query >/dev/null 2>&1 || return

  xfconf-query -c xsettings -p /Net/ThemeName -s Arc-Dark
  xfconf-query -c xsettings -p /Net/IconThemeName -s Qogir-Dark
  xfconf-query -c xsettings -p /Gtk/CursorThemeName -s Qogir-Dark
  xfconf-query -c xsettings -p /Gtk/CursorThemeSize -s 32
  xfconf-query -c xfce4-panel -p /panels/dark-mode -s true

  if command -v gsettings >/dev/null 2>&1; then
    gsettings set org.gnome.desktop.interface gtk-theme Arc-Dark
    gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface cursor-theme Qogir-Dark
    gsettings set org.gnome.desktop.interface cursor-size 32
  fi
}

dotfiles_xfconf_set() {
  local channel="$1"
  local property="$2"
  local type="$3"
  local value="$4"

  if xfconf-query -c "$channel" -p "$property" >/dev/null 2>&1; then
    xfconf-query -c "$channel" -p "$property" -s "$value"
  else
    xfconf-query -c "$channel" -p "$property" -n -t "$type" -s "$value"
  fi
}

dotfiles_xfwm_shortcut_set() {
  local property="$1"
  local action="$2"

  # Xfwm can retain a stale X11 key grab when an existing binding is rewritten.
  xfconf-query -c xfce4-keyboard-shortcuts -p "$property" -r 2>/dev/null || true
  dotfiles_xfconf_set xfce4-keyboard-shortcuts "$property" string "$action"
}

dotfiles_xfce_brightness_floor_value() {
  local backlight
  local max_brightness

  for backlight in /sys/class/backlight/*; do
    [[ -r "$backlight/max_brightness" ]] || continue
    read -r max_brightness <"$backlight/max_brightness"
    [[ "$max_brightness" =~ ^[0-9]+$ ]] || continue
    ((max_brightness > 0)) || continue

    # Keep the panel visible while allowing XFCE below its default 10% floor.
    printf '%d\n' "$(((max_brightness + 99) / 100))"
    return 0
  done

  return 1
}

dotfiles_xfce_shortcuts_configured() {
  [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>Return' 2>/dev/null)" == "exo-open --launch TerminalEmulator" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>l' 2>/dev/null)" == "xflock4" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Shift><Super>s' 2>/dev/null)" == "xfce4-screenshooter -r" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>Left' 2>/dev/null)" == "tile_left_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>Right' 2>/dev/null)" == "tile_right_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>Up' 2>/dev/null)" == "maximize_window_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>Down' 2>/dev/null)" == "hide_window_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>1' 2>/dev/null)" == "workspace_1_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>2' 2>/dev/null)" == "workspace_2_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>3' 2>/dev/null)" == "workspace_3_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Super>4' 2>/dev/null)" == "workspace_4_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Shift><Super>1' 2>/dev/null)" == "move_window_workspace_1_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Shift><Super>2' 2>/dev/null)" == "move_window_workspace_2_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Shift><Super>3' 2>/dev/null)" == "move_window_workspace_3_key" ]] &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/xfwm4/custom/<Shift><Super>4' 2>/dev/null)" == "move_window_workspace_4_key" ]]
}

dotfiles_configure_xfce_qol() {
  local brightness_floor
  local home
  local shortcut

  [[ "$(uname -s)" == "Linux" ]] || return
  [[ "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]] || return
  command -v xfconf-query >/dev/null 2>&1 || return

  home="$(dev_server_home)"
  if brightness_floor="$(dotfiles_xfce_brightness_floor_value)"; then
    dotfiles_xfconf_set xfce4-power-manager \
      /xfce4-power-manager/brightness-slider-min-level int "$brightness_floor"
  fi

  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/profile-on-ac string balanced
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/profile-on-battery string power-saver

  dotfiles_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Super>Return' string 'exo-open --launch TerminalEmulator'
  dotfiles_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Super>l' string xflock4
  dotfiles_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Shift><Super>s' string 'xfce4-screenshooter -r'

  dotfiles_xfwm_shortcut_set \
    '/xfwm4/custom/<Super>Left' tile_left_key
  dotfiles_xfwm_shortcut_set \
    '/xfwm4/custom/<Super>Right' tile_right_key
  dotfiles_xfwm_shortcut_set \
    '/xfwm4/custom/<Super>Up' maximize_window_key
  dotfiles_xfwm_shortcut_set \
    '/xfwm4/custom/<Super>Down' hide_window_key
  for shortcut in 1 2 3 4; do
    dotfiles_xfwm_shortcut_set \
      "/xfwm4/custom/<Super>$shortcut" "workspace_${shortcut}_key"
    dotfiles_xfwm_shortcut_set \
      "/xfwm4/custom/<Shift><Super>$shortcut" \
      "move_window_workspace_${shortcut}_key"
  done

  if command -v xfce4-clipman >/dev/null 2>&1; then
    install -d -m 0755 "$home/.config/autostart"
    rm -f "$home/.config/autostart/xfce4-clipman.desktop"
    rm -f "$home/.config/systemd/user/xfce4-clipman.service"
    dotfiles_install_file \
      "$(dotfiles_asset xfce4-clipman-autostart.desktop)" \
      "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop"
    dotfiles_xfconf_set xfce4-panel \
      /plugins/clipman/settings/history-ignore-primary-clipboard bool true
    dotfiles_xfconf_set xfce4-panel \
      /plugins/clipman/settings/max-images-in-history uint 5
    dotfiles_xfconf_set xfce4-panel \
      /plugins/clipman/settings/max-texts-in-history uint 50
    dotfiles_xfconf_set xfce4-panel \
      /plugins/clipman/settings/save-on-quit bool true
    dotfiles_xfconf_set xfce4-panel \
      /plugins/clipman/tweaks/reorder-items bool true

    shortcut='/commands/custom/<Super>v'
    dotfiles_xfconf_set xfce4-keyboard-shortcuts "$shortcut" string \
      /usr/bin/xfce4-clipman-history

    if ! busctl --user status org.xfce.clipman >/dev/null 2>&1; then
      systemd-run --user --quiet --collect /usr/bin/xfce4-clipman
      for _ in {1..20}; do
        busctl --user status org.xfce.clipman >/dev/null 2>&1 && break
        sleep 0.1
      done
    fi
  fi

  if command -v gammastep >/dev/null 2>&1; then
    install -d -m 0755 \
      "$home/.config/autostart" \
      "$home/.config/gammastep" \
      "$home/.config/systemd/user"
    dotfiles_install_file \
      "$(dotfiles_asset gammastep-autostart.desktop)" \
      "$home/.config/autostart/gammastep.desktop"
    dotfiles_install_file \
      "$(dotfiles_asset gammastep.config)" \
      "$home/.config/gammastep/config.ini"
    dotfiles_install_file \
      "$(dev_server_assets_dir)/systemd-user/gammastep.service" \
      "$home/.config/systemd/user/gammastep.service"
    systemctl --user daemon-reload
    systemctl --user disable gammastep.service >/dev/null 2>&1 || true
    systemctl --user restart gammastep.service
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
  # Retire the old global rewrite. Each remote should retain the transport used
  # when it was cloned, including gh's authenticated HTTPS default.
  git config --global --unset-all url.git@github.com:.insteadOf || true
}

dotfiles_install() {
  local home

  home="$(dev_server_home)"
  dotfiles_install_dirs
  dotfiles_install_file "$(dotfiles_asset zshenv)" "$home/.zshenv"
  dotfiles_install_file "$(dotfiles_asset zshrc)" "$home/.zshrc"
  dotfiles_install_file "$(dotfiles_asset zsh_helpers)" "$home/.zsh_helpers"
  dotfiles_install_file "$(dotfiles_asset p10k.zsh)" "$home/.p10k.zsh"
  dotfiles_install_file "$(dotfiles_asset tmux.conf)" "$home/.tmux.conf"
  dotfiles_install_file "$(dotfiles_asset gitignore_global)" "$home/.gitignore_global"
  dotfiles_install_shell_repos
  dotfiles_install_tmux_plugins
  dotfiles_configure_login_shell
  dotfiles_configure_xfce_theme
  dotfiles_configure_xfce_qol
  dotfiles_configure_ghostty
  dotfiles_configure_xfce_terminal
  dotfiles_configure_git
}

dotfiles_doctor() {
  local brightness_floor
  local home
  local file
  local id
  local branch

  home="$(dev_server_home)"
  for file in .zshenv .zshrc .zsh_helpers .p10k.zsh .tmux.conf .gitignore_global; do
    id="dotfiles.${file#.}"
    if [[ -f "$home/$file" ]]; then
      doctor_pass "$id" "$home/$file"
    else
      doctor_fail "$id" "missing $home/$file"
    fi
  done

  if command -v zsh >/dev/null 2>&1; then
    doctor_local_cmd dotfiles.zsh "zsh config parses" "zsh -n '$home/.zshenv' && zsh -n '$home/.zshrc' && zsh -n '$home/.zsh_helpers'"
    if [[ "$(dotfiles_current_login_shell)" == "$(command -v zsh)" ]]; then
      doctor_pass dotfiles.login-shell "zsh is the login shell"
    else
      doctor_fail dotfiles.login-shell "login shell is $(dotfiles_current_login_shell), expected $(command -v zsh)"
    fi
  else
    doctor_fail dotfiles.zsh "zsh missing"
    doctor_fail dotfiles.login-shell "zsh missing"
  fi

  if [[ "$(uname -s)" == "Linux" && "${XDG_CURRENT_DESKTOP:-}" == *XFCE* ]] &&
    command -v xfconf-query >/dev/null 2>&1; then
    if [[ "$(xfconf-query -c xsettings -p /Net/ThemeName 2>/dev/null)" == "Arc-Dark" ]] &&
      [[ "$(xfconf-query -c xsettings -p /Net/IconThemeName 2>/dev/null)" == "Qogir-Dark" ]] &&
      [[ "$(xfconf-query -c xsettings -p /Gtk/CursorThemeName 2>/dev/null)" == "Qogir-Dark" ]] &&
      [[ "$(xfconf-query -c xsettings -p /Gtk/CursorThemeSize 2>/dev/null)" == "32" ]] &&
      [[ "$(xfconf-query -c xfce4-panel -p /panels/dark-mode 2>/dev/null)" == "true" ]] &&
      [[ "$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)" == "'prefer-dark'" ]] &&
      [[ "$(gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null)" == "'Qogir-Dark'" ]]; then
      doctor_pass dotfiles.desktop-theme "Arc-Dark desktop with Qogir icons and cursor active"
    else
      doctor_fail dotfiles.desktop-theme "dark desktop theme is not fully active"
    fi

    if [[ "$(xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/profile-on-ac 2>/dev/null)" == "balanced" ]] &&
      [[ "$(xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/profile-on-battery 2>/dev/null)" == "power-saver" ]]; then
      doctor_pass dotfiles.power-profiles "balanced on AC and power-saver on battery"
    else
      doctor_fail dotfiles.power-profiles "XFCE power profiles are not fully configured"
    fi

    if dotfiles_xfce_shortcuts_configured; then
      doctor_pass dotfiles.desktop-shortcuts "terminal, lock, screenshot, tiling, and workspace shortcuts active"
    else
      doctor_fail dotfiles.desktop-shortcuts "managed XFCE shortcut layer is incomplete"
    fi

    if brightness_floor="$(dotfiles_xfce_brightness_floor_value)"; then
      if [[ "$(xfconf-query -c xfce4-power-manager -p /xfce4-power-manager/brightness-slider-min-level 2>/dev/null)" == "$brightness_floor" ]]; then
        doctor_pass dotfiles.display-brightness "XFCE minimum backlight is 1% ($brightness_floor)"
      else
        doctor_fail dotfiles.display-brightness "XFCE minimum backlight is not set to 1% ($brightness_floor)"
      fi
    fi

    if [[ "$(xfconf-query -c xfce4-terminal -p /font-use-system 2>/dev/null)" == "false" ]] &&
      [[ "$(xfconf-query -c xfce4-terminal -p /font-name 2>/dev/null)" == "MesloLGS Nerd Font Mono "* ]]; then
      doctor_pass dotfiles.terminal-font "XFCE Terminal uses MesloLGS Nerd Font Mono"
    else
      doctor_fail dotfiles.terminal-font "XFCE Terminal is not using the managed Nerd Font"
    fi

    if command -v xfce4-clipman >/dev/null 2>&1; then
      if [[ -f "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" ]] &&
        grep -Eq '^Exec=(/usr/bin/)?xfce4-clipman$' \
          "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" &&
        grep -Fqx 'Hidden=false' \
          "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" &&
        busctl --user status org.xfce.clipman >/dev/null 2>&1 &&
        [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>v' 2>/dev/null)" == "/usr/bin/xfce4-clipman-history" ]] &&
        [[ "$(xfconf-query -c xfce4-panel -p /plugins/clipman/settings/max-texts-in-history 2>/dev/null)" == "50" ]]; then
        doctor_pass dotfiles.clipboard-history "Clipman active with 50-item history and Super+V search"
      else
        doctor_fail dotfiles.clipboard-history "Clipman history or Super+V shortcut is not active"
      fi
    fi

    if command -v gammastep >/dev/null 2>&1; then
      if [[ -f "$home/.config/gammastep/config.ini" ]] &&
        cmp -s "$(dotfiles_asset gammastep.config)" "$home/.config/gammastep/config.ini" &&
        [[ -f "$home/.config/autostart/gammastep.desktop" ]] &&
        cmp -s "$(dotfiles_asset gammastep-autostart.desktop)" \
          "$home/.config/autostart/gammastep.desktop" &&
        systemctl --user is-active --quiet gammastep.service; then
        doctor_pass dotfiles.night-color "Gammastep active with San Francisco solar schedule"
      else
        doctor_fail dotfiles.night-color "Gammastep configuration or user service is not active"
      fi
    fi
  fi

  if [[ "$(uname -s)" == "Linux" ]] && command -v ghostty >/dev/null 2>&1; then
    if [[ -f "$home/.config/ghostty/config.ghostty" ]] &&
      cmp -s "$(dotfiles_asset ghostty.config)" "$home/.config/ghostty/config.ghostty" &&
      ghostty +show-config --changes-only >/dev/null 2>&1; then
      doctor_pass dotfiles.ghostty-config "managed Ghostty configuration installed"
    else
      doctor_fail dotfiles.ghostty-config "Ghostty configuration is missing or invalid"
    fi

    if [[ "${XDG_CURRENT_DESKTOP:-}" != *XFCE* ]] ||
      [[ "$(xfce4-mime-helper -q TerminalEmulator 2>/dev/null)" == "ghostty" ]]; then
      doctor_pass dotfiles.ghostty-default "Ghostty is the preferred terminal"
    else
      doctor_fail dotfiles.ghostty-default "Ghostty is not the preferred XFCE terminal"
    fi

    if systemctl --user is-enabled --quiet app-com.mitchellh.ghostty.service; then
      doctor_pass dotfiles.ghostty-service "Ghostty user service enabled"
    else
      doctor_fail dotfiles.ghostty-service "Ghostty user service is not enabled"
    fi
  fi

  branch="$(git config --global init.defaultBranch || true)"
  if [[ "$branch" == "main" ]]; then
    doctor_pass dotfiles.git "git defaults configured"
  else
    doctor_fail dotfiles.git "git init.defaultBranch is ${branch:-unset}, expected main"
  fi
}
