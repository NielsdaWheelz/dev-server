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

dotfiles_xfce_workstation() {
  declare -F platform_id >/dev/null 2>&1 && [[ "$(platform_id)" == arch ]]
}

dotfiles_xfce_session_active() {
  command -v busctl >/dev/null 2>&1 &&
    busctl --user status org.xfce.SessionManager >/dev/null 2>&1
}

dotfiles_doctor_xfce_session_capability() {
  local id="$1"
  local configured_check="$2"
  local runtime_check="$3"
  local ready_message="$4"
  local configuration_failure="$5"
  local runtime_failure="$6"
  local inactive_message="$7"

  if ! "$configured_check"; then
    doctor_fail "$id" "$configuration_failure"
  elif "$runtime_check"; then
    doctor_pass "$id" "$ready_message"
  elif dotfiles_xfce_session_active; then
    doctor_fail "$id" "$runtime_failure"
  else
    doctor_warn "$id" "$inactive_message"
  fi
}

dotfiles_configure_xfce_terminal() {
  local current_font
  local font_size

  dotfiles_xfce_workstation || return 0
  require_cmd xfconf-query

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

dotfiles_configure_xfce_ghostty_default() {
  local home
  local helpers_file
  local temporary

  home="$(dev_server_home)"
  helpers_file="$home/.config/xfce4/helpers.rc"
  temporary="$(mktemp "$helpers_file.XXXXXX")"

  if ! printf 'TerminalEmulator=ghostty\n' >"$temporary"; then
    rm -f "$temporary"
    return 1
  fi

  if [[ -f "$helpers_file" ]] &&
    ! awk '
      /^[[:space:]]*\[.*\]/ { next }
      /^[[:space:]]*TerminalEmulator[[:space:]]*=/ { next }
      { print }
    ' "$helpers_file" >>"$temporary"; then
    rm -f "$temporary"
    return 1
  fi

  if [[ -f "$helpers_file" ]] && cmp -s "$temporary" "$helpers_file"; then
    rm -f "$temporary"
    return 0
  fi

  if ! chmod 0644 "$temporary" || ! mv -f "$temporary" "$helpers_file"; then
    rm -f "$temporary"
    return 1
  fi
}

dotfiles_configure_ghostty() {
  local home

  [[ "$(uname -s)" == "Linux" ]] || return 0
  command -v ghostty >/dev/null 2>&1 || return 0

  home="$(dev_server_home)"
  install -d -m 0755 "$home/.config/ghostty"
  dotfiles_install_file "$(dotfiles_asset ghostty.config)" "$home/.config/ghostty/config.ghostty"

  if dotfiles_xfce_workstation; then
    install -d -m 0755 \
      "$home/.config/autostart" \
      "$home/.config/xfce4" \
      "$home/.local/share/xfce4/helpers"
    dotfiles_install_file \
      "$(dotfiles_asset ghostty-autostart.desktop)" \
      "$home/.config/autostart/ghostty.desktop"
    dotfiles_install_file \
      "$(dotfiles_asset ghostty-xfce-helper.desktop)" \
      "$home/.local/share/xfce4/helpers/ghostty.desktop"
    dotfiles_configure_xfce_ghostty_default
    systemctl --user disable app-com.mitchellh.ghostty.service
  else
    systemctl --user enable --now app-com.mitchellh.ghostty.service
  fi
}

dotfiles_ghostty_service_configured() {
  local enabled
  local home

  home="$(dev_server_home)"
  if ! dotfiles_xfce_workstation; then
    systemctl --user is-enabled --quiet app-com.mitchellh.ghostty.service
    return
  fi

  [[ -f "$home/.config/autostart/ghostty.desktop" ]] &&
    cmp -s "$(dotfiles_asset ghostty-autostart.desktop)" \
      "$home/.config/autostart/ghostty.desktop" || return 1

  enabled="$(systemctl --user is-enabled app-com.mitchellh.ghostty.service 2>/dev/null || true)"
  [[ "$enabled" == disabled ]]
}

dotfiles_xfce_ghostty_default_configured() {
  local home
  local helper_file
  local helpers_file

  home="$(dev_server_home)"
  helper_file="$home/.local/share/xfce4/helpers/ghostty.desktop"
  helpers_file="$home/.config/xfce4/helpers.rc"

  [[ -f "$helpers_file" && -f "$helper_file" ]] &&
    awk '
      /^[[:space:]]*\[.*\]/ { invalid_section = 1; next }
      /^[[:space:]]*TerminalEmulator[[:space:]]*=/ {
        value = $0
        sub(/^[[:space:]]*TerminalEmulator[[:space:]]*=[[:space:]]*/, "", value)
        sub(/[[:space:]]*$/, "", value)
        count++
        if (value == "ghostty") matches++
      }
      END { exit(!invalid_section && count == 1 && matches == 1 ? 0 : 1) }
    ' "$helpers_file" &&
    cmp -s "$(dotfiles_asset ghostty-xfce-helper.desktop)" "$helper_file"
}

dotfiles_configure_xfce_theme() {
  dotfiles_xfce_workstation || return 0
  require_cmd xfconf-query

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
    xfconf-query -c "$channel" -p "$property" -t "$type" -s "$value"
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

dotfiles_xfce_idle_policy_configured() {
  local power=/xfce4-power-manager

  [[ "$(xfconf-query -c xfce4-power-manager -p "$power/dpms-enabled" 2>/dev/null)" == "true" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/dpms-on-ac-sleep" 2>/dev/null)" == "0" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/dpms-on-ac-off" 2>/dev/null)" == "5" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/dpms-on-battery-sleep" 2>/dev/null)" == "0" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/dpms-on-battery-off" 2>/dev/null)" == "2" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/inactivity-on-ac" 2>/dev/null)" == "0" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/inactivity-on-battery" 2>/dev/null)" == "5" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/inactivity-sleep-mode-on-ac" 2>/dev/null)" == "1" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/inactivity-sleep-mode-on-battery" 2>/dev/null)" == "1" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/lock-screen-suspend-hibernate" 2>/dev/null)" == "true" ]] &&
    [[ "$(xfconf-query -c xfce4-power-manager -p "$power/presentation-mode" 2>/dev/null)" == "false" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /saver/enabled 2>/dev/null)" == "true" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /saver/mode 2>/dev/null)" == "0" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /saver/idle-activation/enabled 2>/dev/null)" == "true" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /saver/idle-activation/delay 2>/dev/null)" == "30" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /lock/enabled 2>/dev/null)" == "true" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /lock/saver-activation/enabled 2>/dev/null)" == "true" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /lock/saver-activation/delay 2>/dev/null)" == "0" ]] &&
    [[ "$(xfconf-query -c xfce4-screensaver -p /lock/sleep-activation 2>/dev/null)" == "true" ]]
}

dotfiles_xfce_idle_consumers_active() {
  command -v busctl >/dev/null 2>&1 &&
    busctl --user status org.xfce.PowerManager >/dev/null 2>&1 &&
    busctl --user status org.xfce.ScreenSaver >/dev/null 2>&1
}

dotfiles_configure_xfce_idle_policy() {
  dotfiles_xfce_workstation || return 0
  require_cmd xfconf-query

  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-enabled bool true
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-ac-sleep uint 0
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-ac-off uint 5
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-battery-sleep uint 0
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-battery-off uint 2
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-on-ac uint 0
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-on-battery uint 5
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-sleep-mode-on-ac uint 1
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-sleep-mode-on-battery uint 1
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/lock-screen-suspend-hibernate bool true
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/presentation-mode bool false

  dotfiles_xfconf_set xfce4-screensaver /saver/enabled bool true
  dotfiles_xfconf_set xfce4-screensaver /saver/mode int 0
  dotfiles_xfconf_set xfce4-screensaver \
    /saver/idle-activation/enabled bool true
  dotfiles_xfconf_set xfce4-screensaver \
    /saver/idle-activation/delay int 30
  dotfiles_xfconf_set xfce4-screensaver /lock/enabled bool true
  dotfiles_xfconf_set xfce4-screensaver \
    /lock/saver-activation/enabled bool true
  dotfiles_xfconf_set xfce4-screensaver \
    /lock/saver-activation/delay int 0
  dotfiles_xfconf_set xfce4-screensaver /lock/sleep-activation bool true
}

dotfiles_doctor_xfce_idle_policy() {
  dotfiles_xfce_workstation || return 0
  dotfiles_doctor_xfce_session_capability \
    dotfiles.idle-policy \
    dotfiles_xfce_idle_policy_configured \
    dotfiles_xfce_idle_consumers_active \
    "display off 5m AC/2m battery, idle lock 30m, suspend never AC/5m battery" \
    "XFCE display, lock, suspend, or presentation-mode configuration is incomplete" \
    "XFCE power-manager or screensaver ownership is missing from the active session" \
    "policy configured; runtime ownership awaits an XFCE login"
}

dotfiles_retire_xfce_session_services() {
  local home
  local unit
  local units=(xfce4-clipman.service gammastep.service)

  home="$(dev_server_home)"
  require_cmd systemctl
  for unit in "${units[@]}"; do
    systemctl --user disable --now "$unit" >/dev/null 2>&1 || true
    rm -f "$home/.config/systemd/user/$unit"
  done
  systemctl --user daemon-reload
  for unit in "${units[@]}"; do
    systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  done
}

dotfiles_configure_xfce_qol() {
  local brightness_floor
  local home
  local shortcut

  dotfiles_xfce_workstation || return 0
  require_cmd xfconf-query
  dotfiles_retire_xfce_session_services

  home="$(dev_server_home)"
  if brightness_floor="$(dotfiles_xfce_brightness_floor_value)"; then
    dotfiles_xfconf_set xfce4-power-manager \
      /xfce4-power-manager/brightness-slider-min-level int "$brightness_floor"
  fi

  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/profile-on-ac string balanced
  dotfiles_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/profile-on-battery string power-saver
  dotfiles_configure_xfce_idle_policy

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
  fi

  if command -v gammastep >/dev/null 2>&1; then
    install -d -m 0755 \
      "$home/.config/autostart" \
      "$home/.config/gammastep"
    dotfiles_install_file \
      "$(dotfiles_asset gammastep-autostart.desktop)" \
      "$home/.config/autostart/gammastep.desktop"
    dotfiles_install_file \
      "$(dotfiles_asset gammastep.config)" \
      "$home/.config/gammastep/config.ini"
  fi
}

dotfiles_xfce_user_service_retired() {
  local unit="$1"
  local path

  path="$(dev_server_home)/.config/systemd/user/$unit"
  [[ ! -e "$path" && ! -L "$path" ]]
}

dotfiles_clipboard_history_configured() {
  local home

  home="$(dev_server_home)"
  [[ -f "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" ]] &&
    [[ ! -L "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" ]] &&
    cmp -s "$(dotfiles_asset xfce4-clipman-autostart.desktop)" \
      "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" &&
    dotfiles_xfce_user_service_retired xfce4-clipman.service &&
    [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p '/commands/custom/<Super>v' 2>/dev/null)" == "/usr/bin/xfce4-clipman-history" ]] &&
    [[ "$(xfconf-query -c xfce4-panel -p /plugins/clipman/settings/max-texts-in-history 2>/dev/null)" == "50" ]]
}

dotfiles_clipboard_history_runtime_active() {
  busctl --user status org.xfce.clipman >/dev/null 2>&1
}

dotfiles_doctor_xfce_clipboard_history() {
  dotfiles_doctor_xfce_session_capability \
    dotfiles.clipboard-history \
    dotfiles_clipboard_history_configured \
    dotfiles_clipboard_history_runtime_active \
    "Clipman active with 50-item history and Super+V search" \
    "Clipman autostart, history, shortcut, or retired-service state is incomplete" \
    "Clipman is not active in the current XFCE session" \
    "configured; runtime awaits an XFCE login"
}

dotfiles_gammastep_configured() {
  local home

  home="$(dev_server_home)"
  [[ -f "$home/.config/gammastep/config.ini" ]] &&
    [[ ! -L "$home/.config/gammastep/config.ini" ]] &&
    cmp -s "$(dotfiles_asset gammastep.config)" \
      "$home/.config/gammastep/config.ini" &&
    [[ -f "$home/.config/autostart/gammastep.desktop" ]] &&
    [[ ! -L "$home/.config/autostart/gammastep.desktop" ]] &&
    cmp -s "$(dotfiles_asset gammastep-autostart.desktop)" \
      "$home/.config/autostart/gammastep.desktop" &&
    dotfiles_xfce_user_service_retired gammastep.service
}

dotfiles_gammastep_runtime_active() {
  pgrep -u "$(id -u)" -x gammastep >/dev/null 2>&1
}

dotfiles_doctor_xfce_night_color() {
  dotfiles_doctor_xfce_session_capability \
    dotfiles.night-color \
    dotfiles_gammastep_configured \
    dotfiles_gammastep_runtime_active \
    "Gammastep active with San Francisco solar schedule" \
    "Gammastep configuration, autostart, or retired-service state is incomplete" \
    "Gammastep is not active in the current XFCE session" \
    "configured; runtime awaits an XFCE login"
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

  if dotfiles_xfce_workstation && ! command -v xfconf-query >/dev/null 2>&1; then
    doctor_fail dotfiles.xfce-config "xfconf-query is missing on the declared XFCE workstation"
  fi

  if dotfiles_xfce_workstation && command -v xfconf-query >/dev/null 2>&1; then
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

    dotfiles_doctor_xfce_idle_policy

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
      dotfiles_doctor_xfce_clipboard_history
    fi

    if command -v gammastep >/dev/null 2>&1; then
      dotfiles_doctor_xfce_night_color
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

    if ! dotfiles_xfce_workstation || dotfiles_xfce_ghostty_default_configured; then
      doctor_pass dotfiles.ghostty-default "Ghostty is the preferred terminal"
    else
      doctor_fail dotfiles.ghostty-default "Ghostty is not the preferred XFCE terminal"
    fi

    if dotfiles_ghostty_service_configured; then
      if dotfiles_xfce_workstation; then
        doctor_pass dotfiles.ghostty-service "XFCE starts the Ghostty user service after login"
      else
        doctor_pass dotfiles.ghostty-service "Ghostty user service enabled"
      fi
    else
      if dotfiles_xfce_workstation; then
        doctor_fail dotfiles.ghostty-service "Ghostty XFCE autostart is missing or stale systemd enablement remains"
      else
        doctor_fail dotfiles.ghostty-service "Ghostty user service is not enabled"
      fi
    fi
  fi

  branch="$(git config --global init.defaultBranch || true)"
  if [[ "$branch" == "main" ]]; then
    doctor_pass dotfiles.git "git defaults configured"
  else
    doctor_fail dotfiles.git "git init.defaultBranch is ${branch:-unset}, expected main"
  fi
}
