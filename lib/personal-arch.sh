#!/usr/bin/env bash

: "${dev_server_root:=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

personal_arch_desktop_deferred=0
personal_arch_reboot_deferred=0

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
    security/workstation-sshd.conf
    security/arch-public.xml
    security/arch-docker-ingress.xml
  )

  personal_arch_owned_host || die "workstation apply supports only the owned arch host"

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

  dev_server_validate_active_sha dracut
  dev_server_validate_active_sha zram
}

personal_arch_require_runtime() {
  require_cmd cursor
  require_cmd busctl
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

}

personal_arch_validate_inputs() {
  personal_arch_validate_declared_inputs
  personal_arch_require_runtime
}

personal_arch_install_root_file() {
  local source="$1"
  local target="$2"
  local mode="$3"

  atomic_install_file_as_root "$source" "$target" "$mode"
  # Assigned by atomic_install_file_as_root.
  # shellcheck disable=SC2154
  case "$dev_server_install_status" in
  INSTALLED | UPDATED)
    render_result "$dev_server_install_status" "$target"
    ;;
  UP\ TO\ DATE) ;;
  *) die "invalid install result for $target: $dev_server_install_status" ;;
  esac
}

personal_arch_record_security_identity() (
  local desired="$1" target="$2" temporary
  temporary="$(mktemp -t dev-server-security.XXXXXX)" || return 1
  trap 'rm -f "$temporary"' EXIT
  printf '%s\n' "$desired" >"$temporary"
  atomic_install_file_as_root "$temporary" "$target" 0600
)

personal_arch_reboot_pending() {
  [[ ! -d "/usr/lib/modules/$(uname -r)" ]]
}

personal_arch_boot_consumed() {
  (($# == 2)) || die 'personal_arch_boot_consumed needs privilege and path'
  local privilege="$1"
  local path="$2"
  local boot_time
  local file_time

  boot_time="$(awk '$1 == "btime" { print $2; exit }' /proc/stat)"
  file_time="$(_dev_server_run "$privilege" stat -c '%Y' "$path")" ||
    die "could not inspect boot identity input: $path"
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
        personal_arch_reboot_deferred=1
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
  local home asset target

  home="$(dev_server_home)"
  ensure_directory "$home/.config/autostart" 0755
  ensure_directory "$home/.config/gammastep" 0755
  ensure_directory "$home/.config/ghostty" 0755
  ensure_directory "$home/.config/xfce4" 0755
  ensure_directory "$home/.local/share" 0755
  ensure_directory "$home/.local/share/xfce4" 0755
  ensure_directory "$home/.local/share/xfce4/helpers" 0755

  while read -r asset target; do
    install_managed_file "$(personal_arch_asset "dotfiles/$asset")" \
      "$home/$target" 0644 desktop.session
    if [[ "$dev_server_install_status" != 'UP TO DATE' ]]; then
      personal_arch_desktop_deferred=1
    fi
  done <<'FILES'
gammastep-autostart.desktop .config/autostart/gammastep.desktop
gammastep.config .config/gammastep/config.ini
ghostty-autostart.desktop .config/autostart/ghostty.desktop
ghostty.config .config/ghostty/config.ghostty
ghostty-xfce-helper.desktop .local/share/xfce4/helpers/ghostty.desktop
xfce4-clipman-autostart.desktop .config/autostart/xfce4-clipman-plugin-autostart.desktop
xfce4-helpers.rc .config/xfce4/helpers.rc
FILES
}

personal_arch_configure_cursor() {
  local current_extensions
  local home
  local settings_dir
  local settings_file
  local status

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

  home="$(dev_server_home)"
  settings_dir="$home/.config/Cursor/User"
  settings_file="$settings_dir/settings.json"
  ensure_directory "$home/.config" 0755
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

  require_cmd python3

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
import stat
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

try:
    metadata = os.lstat(source)
except FileNotFoundError:
    value = {}
else:
    if not stat.S_ISREG(metadata.st_mode):
        raise SystemExit(f"Cursor settings file is invalid: {source}")
    if metadata.st_size > 1024 * 1024:
        raise SystemExit(f"Cursor settings file is too large: {source}")
    if metadata.st_size:
        with open(source, "r", encoding="utf-8") as stream:
            value = json.load(stream, object_pairs_hook=unique_object,
                              parse_constant=reject_constant)
    else:
        value = {}
if not isinstance(value, dict):
    raise SystemExit(f"Cursor settings must be an object: {source}")
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

personal_arch_report_touchpad_activation() {
  local status

  if python3 - "$1" <<'PY'; then
import os
from pathlib import Path
import sys

modified = os.stat(sys.argv[1]).st_mtime_ns // 1_000_000_000
boot = next(int(line.split()[1]) for line in Path("/proc/stat").read_text().splitlines()
            if line.startswith("btime "))
ticks_per_second = os.sysconf("SC_CLK_TCK")
for process in Path("/proc").iterdir():
    if not process.name.isdecimal():
        continue
    try:
        record = (process / "stat").read_bytes()
    except (FileNotFoundError, ProcessLookupError):
        continue
    identity, fields = record.rsplit(b") ", 1)
    name = identity.split(b"(", 1)[1]
    fields = fields.split()
    if name != b"Xorg" or fields[0] in (b"Z", b"X"):
        continue
    started = boot + int(fields[19]) // ticks_per_second
    # Equal seconds cannot establish that the configuration predates Xorg.
    if modified >= started:
        raise SystemExit(2)
PY
    return 0
  else
    status=$?
  fi
  ((status == 2)) || die 'could not inspect touchpad policy activation'
  render_result DEFERRED "touchpad policy" \
    'restart the display server or reboot to activate the installed policy'
}

personal_arch_configure_root_files() {
  local dracut_sha

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
  if ! personal_arch_boot_consumed user "$(dev_server_active_dir)/dracut.sha256"; then
    personal_arch_reboot_deferred=1
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
  if ! personal_arch_boot_consumed root /efi/loader/loader.conf; then
    personal_arch_reboot_deferred=1
  fi
  personal_arch_install_root_file \
    "$(personal_arch_asset systemd/zram-generator.conf)" \
    /etc/systemd/zram-generator.conf 0644

  personal_arch_install_root_file \
    "$(personal_arch_asset xorg/90-dev-server-huawei-touchpad.conf)" \
    /etc/X11/xorg.conf.d/90-dev-server-huawei-touchpad.conf 0644
  personal_arch_report_touchpad_activation \
    /etc/X11/xorg.conf.d/90-dev-server-huawei-touchpad.conf
}

personal_arch_configure_zram() {
  local activation_required=1
  local desired_sha

  desired_sha="$(dev_server_sha256 "$(personal_arch_asset systemd/zram-generator.conf)")"
  if dev_server_active_sha_matches zram "$desired_sha"; then
    activation_required=0
  fi

  if systemctl is-active --quiet systemd-zram-setup@zram0.service; then
    if ((activation_required == 0)); then
      return 0
    fi
    if personal_arch_boot_consumed root /etc/systemd/zram-generator.conf; then
      dev_server_record_active_sha zram "$desired_sha"
      return 0
    fi
    personal_arch_reboot_deferred=1
    return 0
  fi
  if ((activation_required)); then
    sudo systemctl daemon-reload
    render_result RELOADED systemd "zram activation inputs changed"
  fi
  if ! sudo systemctl start systemd-zram-setup@zram0.service; then
    if personal_arch_reboot_pending; then
      personal_arch_reboot_deferred=1
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
  local assets strict desired recorded permanent runtime
  local changed=0

  personal_arch_ensure_unit firewalld.service
  assets="$(dev_server_assets_dir)/security"
  personal_arch_install_root_file "$assets/arch-public.xml" \
    /etc/firewalld/zones/public.xml 0644
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || changed=1
  if [[ ! -d /etc/firewalld/policies ]]; then
    sudo mkdir -m 0755 /etc/firewalld/policies
  fi
  personal_arch_install_root_file "$assets/arch-docker-ingress.xml" \
    /etc/firewalld/policies/dev-server-docker.xml 0644
  [[ "$dev_server_install_status" == 'UP TO DATE' ]] || changed=1

  strict="$(sudo busctl get-property org.fedoraproject.FirewallD1 \
    /org/fedoraproject/FirewallD1/config org.fedoraproject.FirewallD1.config StrictForwardPorts)"
  if [[ "$strict" != 's "yes"' ]]; then
    sudo busctl set-property org.fedoraproject.FirewallD1 \
      /org/fedoraproject/FirewallD1/config org.fedoraproject.FirewallD1.config StrictForwardPorts s yes
    render_result CHANGED firewalld 'published docker ports require explicit firewall permission'
    changed=1
  fi
  if [[ "$(sudo firewall-cmd --get-default-zone)" != public ]]; then
    sudo firewall-cmd --set-default-zone=public >/dev/null
    render_result CHANGED firewalld 'public is the default zone'
    changed=1
  fi
  sudo firewall-cmd --check-config >/dev/null

  # The receipt makes a failed reload retryable even after files were installed.
  sudo install -d -m 0700 /var/lib/dev-server /var/lib/dev-server/active
  desired="$(cat "$assets/arch-public.xml" "$assets/arch-docker-ingress.xml" | sha256sum | awk '{print $1}')"
  recorded="$(sudo cat /var/lib/dev-server/active/arch-firewall.sha256 2>/dev/null || true)"
  permanent="$(sudo firewall-cmd --permanent --zone=public --list-all | sed '1d; /interfaces:/d')"
  runtime="$(sudo firewall-cmd --zone=public --list-all | sed '1d; /interfaces:/d')"
  if ((changed)) || [[ "$desired" != "$recorded" || "$permanent" != "$runtime" ]]; then
    sudo firewall-cmd --reload >/dev/null
    render_result RELOADED firewalld
  fi

  permanent="$(sudo firewall-cmd --permanent --zone=public --list-all | sed '1d; /interfaces:/d')"
  runtime="$(sudo firewall-cmd --zone=public --list-all | sed '1d; /interfaces:/d')"
  [[ "$permanent" == "$runtime" ]] || die 'public firewalld runtime differs from its declaration'
  permanent="$(sudo firewall-cmd --permanent --policy=dev-server-docker --list-all | sed '1d')"
  if runtime="$(sudo firewall-cmd --policy=dev-server-docker --list-all 2>/dev/null)"; then
    runtime="$(sed '1d' <<<"$runtime")"
  else
    runtime=''
  fi
  if [[ "$permanent" != "$runtime" ]]; then
    sudo firewall-cmd --reload >/dev/null
    runtime="$(sudo firewall-cmd --policy=dev-server-docker --list-all | sed '1d')"
    [[ "$permanent" == "$runtime" ]] || die 'docker ingress policy failed to activate'
    render_result RELOADED firewalld
  fi
  if [[ "$recorded" != "$desired" ]]; then
    personal_arch_record_security_identity "$desired" /var/lib/dev-server/active/arch-firewall.sha256
  fi
}

personal_arch_configure_ssh() {
  local source desired recorded effective address
  source="$(dev_server_assets_dir)/security/workstation-sshd.conf"
  sudo /usr/bin/sshd -t -f "$source"
  personal_arch_install_root_file "$source" /etc/ssh/sshd_config.d/00-dev-server.conf 0644
  sudo /usr/bin/sshd -t
  for address in 100.74.175.11 fd7a:115c:a1e0::3138:af0b; do
    effective="$(sudo /usr/bin/sshd -T -C "user=nnandal,host=macbook,addr=$address" |
      awk '{$1=tolower($1); print}')"
    for desired in 'passwordauthentication no' 'kbdinteractiveauthentication no' \
      'permitrootlogin no' 'pubkeyauthentication yes' 'allowusers nnandal' 'gatewayports no'; do
      grep -Fxq "$desired" <<<"$effective" || die "effective ssh policy differs: $desired"
    done
  done
  sudo install -d -m 0700 /var/lib/dev-server /var/lib/dev-server/active
  desired="$(dev_server_sha256 "$source")"
  recorded="$(sudo cat /var/lib/dev-server/active/ssh.sha256 2>/dev/null || true)"
  if [[ "$desired" != "$recorded" ]]; then
    sudo systemctl reload sshd.service
    personal_arch_record_security_identity "$desired" /var/lib/dev-server/active/ssh.sha256
    render_result RELOADED sshd.service
  fi
}

personal_arch_configure_services() {
  local user

  personal_arch_configure_zram
  personal_arch_configure_firewall
  personal_arch_ensure_unit sshd.service
  personal_arch_configure_ssh
  personal_arch_ensure_unit docker.service 1 || [[ $? == 2 ]]
  personal_arch_ensure_unit tailscaled.service 1 || [[ $? == 2 ]]

  user="$(id -un)"
  if ! id -nG "$user" | tr ' ' '\n' | grep -Fqx docker; then
    sudo usermod -aG docker "$user"
    render_result CHANGED "$user" "added to docker group"
    # Read by workstation_report_deferrals.
    # shellcheck disable=SC2034
    personal_arch_desktop_deferred=1
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
    # Read by workstation_report_deferrals.
    # shellcheck disable=SC2034
    personal_arch_reboot_deferred=1
  fi
}
