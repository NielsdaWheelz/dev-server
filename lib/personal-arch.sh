#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

personal_arch_asset() {
  printf '%s/assets/%s\n' "$dev_server_root" "$1"
}

personal_arch_owned_host() {
  [[ "$(uname -s)" == Linux ]] &&
    [[ -f /etc/arch-release ]] &&
    [[ -r /sys/class/dmi/id/sys_vendor ]] &&
    [[ -r /sys/class/dmi/id/product_name ]] &&
    [[ "$(</sys/class/dmi/id/sys_vendor)" == HUAWEI ]] &&
    [[ "$(</sys/class/dmi/id/product_name)" == MACH-WX9 ]]
}

personal_arch_validate_declared_inputs() {
  local asset
  local esp_options
  local -a assets=(
    dracut/90-dev-server.conf
    endeavouros/eos-update.conf
    reflector/reflector.conf
    systemd-boot/loader.conf
    systemd/zram-generator.conf
    xorg/90-dev-server-huawei-touchpad.conf
    dotfiles/gammastep-autostart.desktop
    dotfiles/gammastep.config
    dotfiles/ghostty-autostart.desktop
    dotfiles/ghostty.config
    dotfiles/ghostty-xfce-helper.desktop
    dotfiles/xfce4-clipman-autostart.desktop
    dotfiles/xfce4-helpers.rc
  )

  personal_arch_owned_host || die "workstation apply supports only the owned arch host"
  [[ -d /efi/loader ]] || die "owned arch host is not using systemd-boot at /efi/loader"

  require_cmd findmnt
  [[ "$(findmnt -n -o FSTYPE --target /efi)" == vfat ]] ||
    die "owned arch ESP at /efi is not vfat"
  esp_options="$(findmnt -n -o OPTIONS --target /efi)"
  case ",$esp_options," in
  *,fmask=0137,*) ;;
  *) die "owned arch ESP at /efi must use fmask=0137" ;;
  esac
  case ",$esp_options," in
  *,dmask=0027,*) ;;
  *) die "owned arch ESP at /efi must use dmask=0027" ;;
  esac

  for asset in "${assets[@]}"; do
    asset="$(personal_arch_asset "$asset")"
    [[ -f "$asset" && ! -L "$asset" ]] || die "invalid personal asset: $asset"
  done

  personal_arch_validate_cursor_state

  dev_server_validate_active_sha dracut
  dev_server_validate_active_sha zram
}

personal_arch_validate_cursor_state() {
  local home settings_file

  home="$(dev_server_home)"
  settings_file="$home/.config/Cursor/User/settings.json"
  require_cmd python3
  python3 - "$home" "$settings_file" <<'PY' ||
import json
import os
import stat
import sys

home, settings = map(os.path.abspath, sys.argv[1:])

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON key: {key}")
        value[key] = item
    return value

def reject_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")

for path in (os.path.join(home, ".config"),
             os.path.join(home, ".config", "Cursor"),
             os.path.join(home, ".config", "Cursor", "User")):
    try:
        mode = os.lstat(path).st_mode
    except FileNotFoundError:
        continue
    if not stat.S_ISDIR(mode):
        raise SystemExit(f"Cursor settings directory is invalid: {path}")

try:
    metadata = os.lstat(settings)
except FileNotFoundError:
    raise SystemExit(0)
if not stat.S_ISREG(metadata.st_mode):
    raise SystemExit(f"Cursor settings file is invalid: {settings}")
if metadata.st_size == 0:
    raise SystemExit(0)
if metadata.st_size > 1024 * 1024:
    raise SystemExit(f"Cursor settings file is too large: {settings}")
with open(settings, "r", encoding="utf-8") as stream:
    value = json.load(stream, object_pairs_hook=unique_object,
                      parse_constant=reject_constant)
if not isinstance(value, dict):
    raise SystemExit(f"Cursor settings must be an object: {settings}")
PY
    die "Cursor settings topology or schema is invalid: $settings_file"
}

personal_arch_require_runtime() {
  require_cmd cursor
  require_cmd docker
  require_cmd dracut
  require_cmd eos-update
  require_cmd firewall-cmd
  require_cmd gammastep
  require_cmd ghostty
  require_cmd gsettings
  require_cmd stat
  require_cmd sudo
  require_cmd systemctl
  require_cmd xfce4-clipman
  require_cmd xfconf-query
  require_cmd xinput

}

personal_arch_validate_inputs() {
  personal_arch_validate_declared_inputs
  personal_arch_require_runtime
}

personal_arch_install_root_file() {
  local source="$1"
  local target="$2"
  local mode="$3"
  local change_id="${4:-}"

  atomic_install_file_as_root "$source" "$target" "$mode"
  # Assigned by atomic_install_file_as_root.
  # shellcheck disable=SC2154
  case "$dev_server_install_status" in
  INSTALLED | UPDATED)
    render_result "$dev_server_install_status" "$target"
    [[ -z "$change_id" ]] || record_change "$change_id"
    ;;
  UP\ TO\ DATE) ;;
  *) die "invalid install result for $target: $dev_server_install_status" ;;
  esac
}

personal_arch_reboot_pending() {
  [[ ! -d "/usr/lib/modules/$(uname -r)" ]]
}

personal_arch_boot_consumed() {
  local path="$1"
  local boot_time
  local file_time

  boot_time="$(awk '$1 == "btime" { print $2; exit }' /proc/stat)"
  file_time="$(stat -c '%Y' "$path")"
  [[ "$boot_time" =~ ^[0-9]+$ && "$file_time" =~ ^[0-9]+$ ]] ||
    die "could not compare boot identity for $path"
  ((boot_time >= file_time))
}

personal_arch_intel_cpu() {
  grep -Eqm1 '^vendor_id[[:space:]]*:?[[:space:]]+GenuineIntel$' /proc/cpuinfo
}

personal_arch_ensure_unit() {
  local unit="$1"
  local defer_for_reboot="${2:-0}"

  if ! systemctl is-enabled --quiet "$unit"; then
    sudo systemctl enable "$unit" || die "failed to enable $unit"
    render_result CHANGED "$unit" enabled
  fi

  if ! systemctl is-active --quiet "$unit"; then
    if ! sudo systemctl start "$unit"; then
      if [[ "$defer_for_reboot" == 1 ]] && personal_arch_reboot_pending; then
        record_change system.reboot
        return 2
      fi
      die "failed to start $unit"
    fi
    render_result STARTED "$unit"
  fi

  systemctl is-enabled --quiet "$unit" || die "$unit is not enabled"
  systemctl is-active --quiet "$unit" || die "$unit is not active"
}

personal_arch_xfconf_set() {
  local channel="$1"
  local property="$2"
  local type="$3"
  local value="$4"
  local current

  if current="$(xfconf-query -c "$channel" -p "$property" 2>/dev/null)"; then
    [[ "$current" == "$value" ]] && return 0
    xfconf-query -c "$channel" -p "$property" -t "$type" -s "$value"
  else
    xfconf-query -c "$channel" -p "$property" -n -t "$type" -s "$value"
  fi
  personal_arch_desktop_changed=1
}

personal_arch_xfwm_shortcut() {
  local property="$1"
  local value="$2"

  [[ "$(xfconf-query -c xfce4-keyboard-shortcuts -p "$property" 2>/dev/null || true)" == "$value" ]] &&
    return 0
  xfconf-query -c xfce4-keyboard-shortcuts -p "$property" -r 2>/dev/null || true
  xfconf-query -c xfce4-keyboard-shortcuts -p "$property" \
    -n -t string -s "$value"
  personal_arch_desktop_changed=1
}

personal_arch_gsettings_set() {
  local schema="$1"
  local key="$2"
  local value="$3"

  [[ "$(gsettings get "$schema" "$key")" == "$value" ]] && return 0
  gsettings set "$schema" "$key" "$value"
  personal_arch_desktop_changed=1
}

personal_arch_brightness_floor() {
  local backlight
  local maximum

  for backlight in /sys/class/backlight/*; do
    [[ -r "$backlight/max_brightness" ]] || continue
    read -r maximum <"$backlight/max_brightness"
    [[ "$maximum" =~ ^[0-9]+$ ]] || continue
    ((maximum > 0)) || continue
    printf '%d\n' "$(((maximum + 99) / 100))"
    return 0
  done
  return 1
}

personal_arch_configure_xfce() {
  local brightness_floor
  local current_font
  local font_size
  local workspace

  personal_arch_desktop_changed=0

  personal_arch_xfconf_set xsettings /Net/ThemeName string Arc-Dark
  personal_arch_xfconf_set xsettings /Net/IconThemeName string Qogir-Dark
  personal_arch_xfconf_set xsettings /Gtk/CursorThemeName string Qogir-Dark
  personal_arch_xfconf_set xsettings /Gtk/CursorThemeSize int 32
  personal_arch_xfconf_set xfce4-panel /panels/dark-mode bool true

  personal_arch_gsettings_set org.gnome.desktop.interface gtk-theme "'Arc-Dark'"
  personal_arch_gsettings_set org.gnome.desktop.interface color-scheme "'prefer-dark'"
  personal_arch_gsettings_set org.gnome.desktop.interface cursor-theme "'Qogir-Dark'"
  personal_arch_gsettings_set org.gnome.desktop.interface cursor-size 32

  if brightness_floor="$(personal_arch_brightness_floor)"; then
    personal_arch_xfconf_set xfce4-power-manager \
      /xfce4-power-manager/brightness-slider-min-level int "$brightness_floor"
  fi
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/profile-on-ac string balanced
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/profile-on-battery string power-saver
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-enabled bool true
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-ac-sleep uint 0
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-ac-off uint 5
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-battery-sleep uint 0
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/dpms-on-battery-off uint 2
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-on-ac uint 0
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-on-battery uint 5
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-sleep-mode-on-ac uint 1
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/inactivity-sleep-mode-on-battery uint 1
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/lock-screen-suspend-hibernate bool true
  personal_arch_xfconf_set xfce4-power-manager \
    /xfce4-power-manager/presentation-mode bool false

  personal_arch_xfconf_set xfce4-screensaver /saver/enabled bool true
  personal_arch_xfconf_set xfce4-screensaver /saver/mode int 0
  personal_arch_xfconf_set xfce4-screensaver \
    /saver/idle-activation/enabled bool true
  personal_arch_xfconf_set xfce4-screensaver \
    /saver/idle-activation/delay int 30
  personal_arch_xfconf_set xfce4-screensaver /lock/enabled bool true
  personal_arch_xfconf_set xfce4-screensaver \
    /lock/saver-activation/enabled bool true
  personal_arch_xfconf_set xfce4-screensaver \
    /lock/saver-activation/delay int 0
  personal_arch_xfconf_set xfce4-screensaver /lock/sleep-activation bool true

  personal_arch_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Super>Return' string 'exo-open --launch TerminalEmulator'
  personal_arch_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Super>l' string xflock4
  personal_arch_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Shift><Super>s' string 'xfce4-screenshooter -r'
  personal_arch_xfwm_shortcut '/xfwm4/custom/<Super>Left' tile_left_key
  personal_arch_xfwm_shortcut '/xfwm4/custom/<Super>Right' tile_right_key
  personal_arch_xfwm_shortcut '/xfwm4/custom/<Super>Up' maximize_window_key
  personal_arch_xfwm_shortcut '/xfwm4/custom/<Super>Down' hide_window_key
  for workspace in 1 2 3 4; do
    personal_arch_xfwm_shortcut "/xfwm4/custom/<Super>$workspace" \
      "workspace_${workspace}_key"
    personal_arch_xfwm_shortcut "/xfwm4/custom/<Shift><Super>$workspace" \
      "move_window_workspace_${workspace}_key"
  done

  personal_arch_xfconf_set xfce4-panel \
    /plugins/clipman/settings/history-ignore-primary-clipboard bool true
  personal_arch_xfconf_set xfce4-panel \
    /plugins/clipman/settings/max-images-in-history uint 5
  personal_arch_xfconf_set xfce4-panel \
    /plugins/clipman/settings/max-texts-in-history uint 50
  personal_arch_xfconf_set xfce4-panel \
    /plugins/clipman/settings/save-on-quit bool true
  personal_arch_xfconf_set xfce4-panel \
    /plugins/clipman/tweaks/reorder-items bool true
  personal_arch_xfconf_set xfce4-keyboard-shortcuts \
    '/commands/custom/<Super>v' string /usr/bin/xfce4-clipman-history

  current_font="$(xfconf-query -c xfce4-terminal -p /font-name 2>/dev/null || printf 'Monospace 10')"
  font_size="${current_font##* }"
  [[ "$font_size" =~ ^[0-9]+$ ]] || font_size=10
  personal_arch_xfconf_set xfce4-terminal /font-use-system bool false
  personal_arch_xfconf_set xfce4-terminal /font-name string \
    "MesloLGS Nerd Font Mono $font_size"

  if ((personal_arch_desktop_changed)); then
    render_result CHANGED "XFCE policy"
  fi
}

personal_arch_configure_session_files() {
  local home

  home="$(dev_server_home)"
  ensure_directory "$home/.config/autostart" 0755
  ensure_directory "$home/.config/gammastep" 0755
  ensure_directory "$home/.config/ghostty" 0755
  ensure_directory "$home/.config/xfce4" 0755
  ensure_directory "$home/.local/share" 0755
  ensure_directory "$home/.local/share/xfce4" 0755
  ensure_directory "$home/.local/share/xfce4/helpers" 0755

  install_managed_file "$(personal_arch_asset dotfiles/gammastep-autostart.desktop)" \
    "$home/.config/autostart/gammastep.desktop" 0644 desktop.session
  install_managed_file "$(personal_arch_asset dotfiles/gammastep.config)" \
    "$home/.config/gammastep/config.ini" 0644 desktop.session
  install_managed_file "$(personal_arch_asset dotfiles/ghostty-autostart.desktop)" \
    "$home/.config/autostart/ghostty.desktop" 0644 desktop.session
  install_managed_file "$(personal_arch_asset dotfiles/ghostty.config)" \
    "$home/.config/ghostty/config.ghostty" 0644 desktop.session
  install_managed_file "$(personal_arch_asset dotfiles/ghostty-xfce-helper.desktop)" \
    "$home/.local/share/xfce4/helpers/ghostty.desktop" 0644 desktop.session
  install_managed_file "$(personal_arch_asset dotfiles/xfce4-clipman-autostart.desktop)" \
    "$home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" \
    0644 desktop.session
  install_managed_file "$(personal_arch_asset dotfiles/xfce4-helpers.rc)" \
    "$home/.config/xfce4/helpers.rc" 0644 desktop.session
}

personal_arch_configure_cursor() {
  local current_extensions
  local home
  local settings_dir
  local settings_file
  local status

  personal_arch_validate_cursor_state

  current_extensions="$(cursor --list-extensions --show-versions 2>/dev/null)" ||
    die "could not inspect Cursor extensions"
  if ! grep -Fqx 'anysphere.remote-ssh@1.1.14' <<<"$current_extensions"; then
    if grep -Eq '^anysphere\.remote-ssh@' <<<"$current_extensions"; then
      status=UPDATED
    else
      status=INSTALLED
    fi
    cursor --install-extension anysphere.remote-ssh@1.1.14 --force
    cursor --list-extensions --show-versions 2>/dev/null |
      grep -Fqx 'anysphere.remote-ssh@1.1.14' ||
      die "Cursor Remote SSH extension did not reach version 1.1.14"
    render_result "$status" "Cursor Remote SSH extension" "1.1.14"
  fi

  personal_arch_validate_cursor_state

  home="$(dev_server_home)"
  settings_dir="$home/.config/Cursor/User"
  settings_file="$settings_dir/settings.json"
  ensure_directory "$home/.config/Cursor" 0755
  ensure_directory "$settings_dir" 0755
  status="$(personal_arch_install_cursor_settings "$settings_file")" ||
    die "could not install Cursor settings: $settings_file"
  case "$status" in
  INSTALLED | UPDATED) render_result "$status" "$settings_file" ;;
  UP\ TO\ DATE) ;;
  *) die "invalid install result for $settings_file: $status" ;;
  esac
}

personal_arch_install_cursor_settings() (
  local settings_file="$1"
  local temporary=''

  cleanup_cursor_settings_stage() {
    [[ -z "$temporary" ]] || rm -f -- "$temporary"
  }
  trap cleanup_cursor_settings_stage EXIT
  trap 'exit 129' HUP
  trap 'exit 130' INT
  trap 'exit 143' TERM

  temporary="$(mktemp "$(dirname "$settings_file")/.settings.json.XXXXXX")" ||
    return 1
  python3 - "$settings_file" "$temporary" <<'PY' || return 1
import json
import os
import sys

source, target = sys.argv[1:]

def unique_object(pairs):
    value = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON key: {key}")
        value[key] = item
    return value

def reject_constant(value):
    raise ValueError(f"invalid JSON constant: {value}")

if os.path.getsize(source) if os.path.exists(source) else 0:
    with open(source, "r", encoding="utf-8") as stream:
        value = json.load(stream, object_pairs_hook=unique_object,
                          parse_constant=reject_constant)
else:
    value = {}
value["remote.SSH.remotePlatform"] = {
    "dev-server": "linux",
    "macbook": "macOS",
}
with open(target, "w", encoding="utf-8") as stream:
    json.dump(value, stream, indent=2, ensure_ascii=False)
    stream.write("\n")
PY
  chmod 0600 "$temporary" || return 1
  atomic_install_file "$temporary" "$settings_file" 0644 || return 1
  printf '%s\n' "$dev_server_install_status"
)

personal_arch_apply_touchpad_runtime() {
  local device
  local motion_points_string
  local motion_step
  local source
  local -a motion_points=()

  [[ "${XDG_SESSION_TYPE:-}" == x11 ]] || return 1
  device="$(xinput list --id-only 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null || true)"
  [[ -n "$device" ]] || return 1

  source="$(personal_arch_asset xorg/90-dev-server-huawei-touchpad.conf)"
  motion_points_string="$(awk -F '"' '$2 == "AccelPointsMotion" { print $4; exit }' "$source")"
  motion_step="$(awk -F '"' '$2 == "AccelStepMotion" { print $4; exit }' "$source")"
  read -r -a motion_points <<<"$motion_points_string"
  [[ "${#motion_points[@]}" -ge 2 && -n "$motion_step" ]] ||
    die "invalid touchpad motion curve: $source"

  xinput set-prop --type=float --format=32 "$device" \
    'libinput Accel Custom Fallback Points' 0.0 1.0
  xinput set-prop "$device" 'libinput Accel Custom Fallback Step' 1.0
  xinput set-prop --type=float --format=32 "$device" \
    'libinput Accel Custom Motion Points' "${motion_points[@]}"
  xinput set-prop "$device" 'libinput Accel Custom Motion Step' "$motion_step"
  xinput set-prop --type=float --format=32 "$device" \
    'libinput Accel Custom Scroll Points' 0.0 1.0
  xinput set-prop "$device" 'libinput Accel Custom Scroll Step' 1.0
  xinput set-prop "$device" 'libinput Accel Profile Enabled' 0 0 1
  xinput set-prop "$device" 'libinput Click Method Enabled' 0 1
  xinput set-prop "$device" 'libinput Disable While Typing Enabled' 1
  xinput set-prop "$device" 'libinput Horizontal Scroll Enabled' 1
  xinput set-prop "$device" 'libinput Natural Scrolling Enabled' 1
  xinput set-prop "$device" 'libinput Scroll Method Enabled' 1 0 0
  xinput set-prop "$device" 'libinput Scrolling Pixel Distance' 15
  xinput set-prop "$device" 'libinput Tapping Enabled' 1
  xinput set-prop "$device" 'libinput Tapping Button Mapping Enabled' 1 0
  xinput set-prop "$device" 'libinput Tapping Drag Enabled' 1
  xinput set-prop "$device" 'libinput Tapping Drag Lock Enabled' 0
}

personal_arch_touchpad_runtime_configured() {
  local properties

  [[ "${XDG_SESSION_TYPE:-}" == x11 ]] || return 1
  properties="$(xinput list-props 'SYNA1D31:00 06CB:CD48 Touchpad' 2>/dev/null)" ||
    return 1
  grep -Eq 'libinput Accel Profile Enabled \([0-9]+\):[[:space:]]+0, 0, 1' \
    <<<"$properties" &&
    grep -Eq 'libinput Accel Custom Motion Step \([0-9]+\):[[:space:]]+0\.105000' \
      <<<"$properties" &&
    grep -Eq 'libinput Natural Scrolling Enabled \([0-9]+\):[[:space:]]+1' \
      <<<"$properties" &&
    grep -Eq 'libinput Click Method Enabled \([0-9]+\):[[:space:]]+0, 1' \
      <<<"$properties"
}

personal_arch_configure_root_files() {
  local dracut_sha
  local touchpad_changed=0

  ensure_directory "$(dev_server_home)/.local/state" 0755
  ensure_directory "$(dev_server_home)/.local/state/dev-server" 0700
  ensure_directory "$(dev_server_active_dir)" 0700
  ensure_directory_as_root /etc/dracut.conf.d 0755
  ensure_directory_as_root /etc/systemd 0755
  ensure_directory_as_root /etc/X11/xorg.conf.d 0755
  ensure_directory_as_root /etc/xdg/reflector 0755

  personal_arch_install_root_file \
    "$(personal_arch_asset dracut/90-dev-server.conf)" \
    /etc/dracut.conf.d/90-dev-server.conf 0644
  dracut_sha="$(dev_server_sha256 "$(personal_arch_asset dracut/90-dev-server.conf)")"
  if ! dev_server_active_sha_matches dracut "$dracut_sha"; then
    sudo dracut --regenerate-all --force || die 'failed to regenerate initramfs images'
    dev_server_record_active_sha dracut "$dracut_sha"
    render_result UPDATED initramfs
  fi
  if ! personal_arch_boot_consumed "$(dev_server_active_dir)/dracut.sha256"; then
    record_change system.reboot
  fi

  personal_arch_install_root_file \
    "$(personal_arch_asset endeavouros/eos-update.conf)" \
    /etc/eos-update.conf 0644
  personal_arch_install_root_file \
    "$(personal_arch_asset reflector/reflector.conf)" \
    /etc/xdg/reflector/reflector.conf 0644
  personal_arch_install_root_file \
    "$(personal_arch_asset systemd-boot/loader.conf)" \
    /efi/loader/loader.conf 0640
  if ! personal_arch_boot_consumed /efi/loader/loader.conf; then
    record_change system.reboot
  fi
  personal_arch_install_root_file \
    "$(personal_arch_asset systemd/zram-generator.conf)" \
    /etc/systemd/zram-generator.conf 0644

  personal_arch_install_root_file \
    "$(personal_arch_asset xorg/90-dev-server-huawei-touchpad.conf)" \
    /etc/X11/xorg.conf.d/90-dev-server-huawei-touchpad.conf 0644
  [[ "$dev_server_install_status" == "UP TO DATE" ]] || touchpad_changed=1

  if ((touchpad_changed)) || ! personal_arch_touchpad_runtime_configured; then
    if personal_arch_apply_touchpad_runtime; then
      render_result RELOADED "touchpad policy"
    else
      record_change desktop.session
    fi
  fi
}

personal_arch_configure_zram() {
  local activation_required=1
  local desired_sha

  desired_sha="$(dev_server_sha256 "$(personal_arch_asset systemd/zram-generator.conf)")"
  if dev_server_active_sha_matches zram "$desired_sha"; then
    activation_required=0
  else
    sudo systemctl daemon-reload
    render_result RELOADED systemd "zram activation inputs changed"
  fi

  if systemctl is-active --quiet systemd-zram-setup@zram0.service; then
    if ((activation_required == 0)); then
      return 0
    fi
    if personal_arch_boot_consumed /etc/systemd/zram-generator.conf; then
      dev_server_record_active_sha zram "$desired_sha"
      return 0
    fi
    record_change system.reboot
    return 0
  fi
  if ! sudo systemctl start systemd-zram-setup@zram0.service; then
    if personal_arch_reboot_pending; then
      record_change system.reboot
      return 0
    fi
    die "failed to start systemd-zram-setup@zram0.service"
  fi
  systemctl is-active --quiet systemd-zram-setup@zram0.service ||
    die "systemd-zram-setup@zram0.service is not active"
  dev_server_record_active_sha zram "$desired_sha"
  render_result STARTED systemd-zram-setup@zram0.service
}

personal_arch_configure_firewall() {
  local permanent_status
  local runtime_status

  personal_arch_ensure_unit firewalld.service

  if sudo firewall-cmd --quiet --permanent --zone=public --query-service=ssh; then
    permanent_status=0
  else
    permanent_status=$?
  fi
  if sudo firewall-cmd --quiet --zone=public --query-service=ssh; then
    runtime_status=0
  else
    runtime_status=$?
  fi
  ((permanent_status == 0 || permanent_status == 1)) ||
    die "failed to inspect permanent firewalld SSH policy"
  ((runtime_status == 0 || runtime_status == 1)) ||
    die "failed to inspect runtime firewalld SSH policy"

  if ((permanent_status == 0)); then
    sudo firewall-cmd --quiet --permanent --zone=public --remove-service=ssh
    sudo firewall-cmd --quiet --reload
    render_result CHANGED firewalld "removed public SSH service"
    render_result RELOADED firewalld
  elif ((runtime_status == 0)); then
    sudo firewall-cmd --quiet --zone=public --remove-service=ssh
    render_result RELOADED firewalld "removed transient public SSH service"
  fi

  if sudo firewall-cmd --quiet --permanent --zone=public --query-service=ssh; then
    die "permanent public SSH service remains enabled"
  else
    permanent_status=$?
    ((permanent_status == 1)) || die "failed to verify permanent firewalld SSH policy"
  fi
  if sudo firewall-cmd --quiet --zone=public --query-service=ssh; then
    die "runtime public SSH service remains enabled"
  else
    runtime_status=$?
    ((runtime_status == 1)) || die "failed to verify runtime firewalld SSH policy"
  fi
}

personal_arch_configure_services() {
  local user

  personal_arch_configure_zram
  personal_arch_configure_firewall
  personal_arch_ensure_unit sshd.service
  personal_arch_ensure_unit docker.service 1 || [[ $? == 2 ]]
  personal_arch_ensure_unit tailscaled.service 1 || [[ $? == 2 ]]

  user="$(id -un)"
  if ! id -nG "$user" | tr ' ' '\n' | grep -Fqx docker; then
    sudo usermod -aG docker "$user"
    render_result CHANGED "$user" "added to docker group"
    record_change desktop.session
  fi

  personal_arch_ensure_unit reflector.timer
  personal_arch_ensure_unit fwupd-refresh.timer
  personal_arch_ensure_unit pkgfile-update.timer
  personal_arch_ensure_unit paccache.timer
  personal_arch_ensure_unit smartd.service
  if personal_arch_intel_cpu; then
    personal_arch_ensure_unit thermald.service
  fi
}

personal_arch_apply() {
  personal_arch_validate_inputs
  personal_arch_configure_root_files
  personal_arch_configure_session_files
  personal_arch_configure_cursor
  personal_arch_configure_xfce
  personal_arch_configure_services
  if personal_arch_reboot_pending; then
    record_change system.reboot
  fi
}
