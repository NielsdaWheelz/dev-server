#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d "${TMPDIR:-/tmp}/dev-server-dotfiles.XXXXXX")"
state_file="$fixture/xfconf-state"
calls_file="$fixture/xfconf-calls"
bus_names_file="$fixture/bus-names"
doctor_output="$fixture/doctor-output"
tests_run=0

cleanup() {
  rm -rf -- "$fixture"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_eq() {
  local want="$1"
  local got="$2"
  local label="$3"
  [[ "$got" == "$want" ]] || fail "$label: got <$got>, want <$want>"
}

assert_contains() {
  grep -Fq -- "$2" "$1" || fail "$1 does not contain: $2"
}

pass() {
  tests_run=$((tests_run + 1))
}

# shellcheck source=lib/common.sh
source "$repo_dir/lib/common.sh"
# shellcheck source=lib/doctor.sh
source "$repo_dir/lib/doctor.sh"
# shellcheck source=lib/dotfiles.sh
source "$repo_dir/lib/dotfiles.sh"
doctor_failures=0
doctor_warnings=0

declare -F dotfiles_configure_xfce_idle_policy >/dev/null ||
  fail 'missing focused XFCE idle-policy convergence boundary'
declare -F dotfiles_doctor_xfce_idle_policy >/dev/null ||
  fail 'missing focused XFCE idle-policy doctor boundary'

platform_id() { printf 'arch\n'; }
unset XDG_CURRENT_DESKTOP

: >"$state_file"
: >"$calls_file"
: >"$bus_names_file"

state_get() {
  local channel="$1"
  local property="$2"
  awk -F '|' -v channel="$channel" -v property="$property" '
    $1 == channel && $2 == property { found = 1; type = $3; value = $4 }
    END {
      if (!found) exit 1
      print type "|" value
    }
  ' "$state_file"
}

state_put() {
  local channel="$1"
  local property="$2"
  local type="$3"
  local value="$4"
  local temporary
  temporary="$(mktemp "$fixture/xfconf-state.XXXXXX")"
  awk -F '|' -v channel="$channel" -v property="$property" \
    '!(($1 == channel) && ($2 == property))' "$state_file" >"$temporary"
  printf '%s|%s|%s|%s\n' "$channel" "$property" "$type" "$value" >>"$temporary"
  mv "$temporary" "$state_file"
}

xfconf-query() {
  local channel=""
  local property=""
  local type=""
  local value=""
  local create=0
  local write=0
  local current

  while (($# > 0)); do
    case "$1" in
    -c)
      channel="$2"
      shift 2
      ;;
    -p)
      property="$2"
      shift 2
      ;;
    -n)
      create=1
      shift
      ;;
    -t)
      type="$2"
      shift 2
      ;;
    -s)
      value="$2"
      write=1
      shift 2
      ;;
    *) fail "unexpected xfconf-query argument: $1" ;;
    esac
  done
  [[ -n "$channel" && -n "$property" ]] || fail 'xfconf-query omitted channel or property'

  if ((write == 0)); then
    current="$(state_get "$channel" "$property")" || return 1
    printf '%s\n' "${current#*|}"
    return
  fi

  if ((create)); then
    [[ -n "$type" ]] || fail "xfconf create omitted type: $channel $property"
    ! state_get "$channel" "$property" >/dev/null 2>&1 ||
      fail "xfconf create replaced existing state: $channel $property"
    printf 'create|%s|%s|%s|%s\n' "$channel" "$property" "$type" "$value" >>"$calls_file"
  else
    current="$(state_get "$channel" "$property")" ||
      fail "xfconf set targeted missing state: $channel $property"
    if [[ -z "$type" ]]; then
      type="${current%%|*}"
    fi
    printf 'set|%s|%s|%s|%s\n' "$channel" "$property" "$type" "$value" >>"$calls_file"
  fi
  state_put "$channel" "$property" "$type" "$value"
}

busctl() {
  [[ "$#" == 3 && "$1" == --user && "$2" == status ]] ||
    fail "unexpected busctl invocation: $*"
  grep -Fqx -- "$3" "$bus_names_file"
}

expected_idle_creates() {
  printf '%s\n' \
    'create|xfce4-power-manager|/xfce4-power-manager/dpms-enabled|bool|true' \
    'create|xfce4-power-manager|/xfce4-power-manager/dpms-on-ac-sleep|uint|0' \
    'create|xfce4-power-manager|/xfce4-power-manager/dpms-on-ac-off|uint|5' \
    'create|xfce4-power-manager|/xfce4-power-manager/dpms-on-battery-sleep|uint|0' \
    'create|xfce4-power-manager|/xfce4-power-manager/dpms-on-battery-off|uint|2' \
    'create|xfce4-power-manager|/xfce4-power-manager/inactivity-on-ac|uint|0' \
    'create|xfce4-power-manager|/xfce4-power-manager/inactivity-on-battery|uint|5' \
    'create|xfce4-power-manager|/xfce4-power-manager/inactivity-sleep-mode-on-ac|uint|1' \
    'create|xfce4-power-manager|/xfce4-power-manager/inactivity-sleep-mode-on-battery|uint|1' \
    'create|xfce4-power-manager|/xfce4-power-manager/lock-screen-suspend-hibernate|bool|true' \
    'create|xfce4-power-manager|/xfce4-power-manager/presentation-mode|bool|false' \
    'create|xfce4-screensaver|/saver/enabled|bool|true' \
    'create|xfce4-screensaver|/saver/mode|int|0' \
    'create|xfce4-screensaver|/saver/idle-activation/enabled|bool|true' \
    'create|xfce4-screensaver|/saver/idle-activation/delay|int|30' \
    'create|xfce4-screensaver|/lock/enabled|bool|true' \
    'create|xfce4-screensaver|/lock/saver-activation/enabled|bool|true' \
    'create|xfce4-screensaver|/lock/saver-activation/delay|int|0' \
    'create|xfce4-screensaver|/lock/sleep-activation|bool|true'
}

test_exact_idle_policy_convergence() {
  local expected="$fixture/expected-creates"
  local expected_updates="$fixture/expected-updates"
  expected_idle_creates >"$expected"

  dotfiles_configure_xfce_idle_policy
  cmp -s "$expected" "$calls_file" || fail 'first idle-policy convergence used the wrong properties, types, values, or order'
  dotfiles_xfce_idle_policy_configured || fail 'fresh exact idle policy did not validate'

  : >"$calls_file"
  dotfiles_configure_xfce_idle_policy
  awk -F '|' '{ print "set|" $2 "|" $3 "|" $4 "|" $5 }' "$expected" >"$expected_updates"
  cmp -s "$expected_updates" "$calls_file" || fail 'repeat idle-policy convergence was not a stable update'
  dotfiles_xfce_idle_policy_configured || fail 'repeated exact idle policy did not validate'
  pass
}

test_idle_policy_type_repair() {
  state_put xfce4-power-manager /xfce4-power-manager/dpms-on-ac-off int 5
  : >"$calls_file"

  dotfiles_configure_xfce_idle_policy

  assert_eq 'uint|5' \
    "$(state_get xfce4-power-manager /xfce4-power-manager/dpms-on-ac-off)" \
    'wrong XFConf type was not repaired'
  pass
}

test_idle_policy_drift() {
  state_put xfce4-power-manager /xfce4-power-manager/presentation-mode bool true
  if dotfiles_xfce_idle_policy_configured; then
    fail 'presentation mode bypassed the idle-policy doctor'
  fi
  state_put xfce4-power-manager /xfce4-power-manager/presentation-mode bool false
  state_put xfce4-screensaver /saver/idle-activation/delay int 29
  if dotfiles_xfce_idle_policy_configured; then
    fail 'idle delay drift bypassed the idle-policy doctor'
  fi
  state_put xfce4-screensaver /saver/idle-activation/delay int 30
  pass
}

test_idle_policy_runtime_doctor() {
  printf '%s\n' \
    org.xfce.SessionManager \
    org.xfce.PowerManager \
    org.xfce.ScreenSaver >"$bus_names_file"
  doctor_reset
  dotfiles_doctor_xfce_idle_policy >"$doctor_output"
  assert_eq 0 "$doctor_failures" 'healthy idle-policy doctor failure count'
  assert_eq 0 "$doctor_warnings" 'healthy idle-policy doctor warning count'
  assert_contains "$doctor_output" 'pass  dotfiles.idle-policy'

  printf '%s\n' org.xfce.SessionManager org.xfce.PowerManager >"$bus_names_file"
  doctor_reset
  dotfiles_doctor_xfce_idle_policy >"$doctor_output"
  assert_eq 1 "$doctor_failures" 'missing screensaver owner failure count'
  assert_contains "$doctor_output" 'fail  dotfiles.idle-policy'

  printf '%s\n' org.xfce.SessionManager org.xfce.ScreenSaver >"$bus_names_file"
  doctor_reset
  dotfiles_doctor_xfce_idle_policy >"$doctor_output"
  assert_eq 1 "$doctor_failures" 'missing power-manager owner failure count'
  assert_contains "$doctor_output" 'fail  dotfiles.idle-policy'

  : >"$bus_names_file"
  doctor_reset
  dotfiles_doctor_xfce_idle_policy >"$doctor_output"
  assert_eq 0 "$doctor_failures" 'headless idle-policy doctor failure count'
  assert_eq 1 "$doctor_warnings" 'headless idle-policy doctor warning count'
  assert_contains "$doctor_output" 'warn  dotfiles.idle-policy'

  state_put xfce4-power-manager /xfce4-power-manager/presentation-mode bool true
  doctor_reset
  dotfiles_doctor_xfce_idle_policy >"$doctor_output"
  assert_eq 1 "$doctor_failures" 'headless idle-policy drift failure count'
  assert_eq 0 "$doctor_warnings" 'headless idle-policy drift warning count'
  assert_contains "$doctor_output" 'fail  dotfiles.idle-policy'
  state_put xfce4-power-manager /xfce4-power-manager/presentation-mode bool false
  pass
}

test_declared_platform_boundary() {
  export XDG_CURRENT_DESKTOP=GNOME
  dotfiles_xfce_workstation || fail 'declared Arch workstation depended on transient desktop environment'

  platform_id() { printf 'macos\n'; }
  : >"$calls_file"
  dotfiles_configure_xfce_idle_policy
  [[ ! -s "$calls_file" ]] || fail 'unsupported platform reached XFCE mutation'
  doctor_reset
  dotfiles_doctor_xfce_idle_policy >"$doctor_output"
  assert_eq 0 "$doctor_failures" 'unsupported platform idle doctor failure count'
  [[ ! -s "$doctor_output" ]] || fail 'unsupported platform emitted an idle-policy doctor fact'
  platform_id() { printf 'arch\n'; }
  unset XDG_CURRENT_DESKTOP
  pass
}

test_declared_packages() {
  local package
  for package in xfconf xfce4-power-manager xfce4-screensaver; do
    [[ "$(grep -Fxc -- "$package" "$repo_dir/packages/arch.pacman.txt")" == 1 ]] ||
      fail "Arch package manifest must contain exactly one $package entry"
  done
  pass
}

test_xfce_session_app_convergence() {
  local qol_home="$fixture/xfce-qol-home"
  local systemctl_calls="$fixture/xfce-qol-systemctl-calls"
  local expected_systemctl="$fixture/xfce-qol-systemctl-expected"

  install -d -m 0755 \
    "$qol_home/.config/autostart" \
    "$qol_home/.config/systemd/user"
  printf 'retired clipman service\n' >"$qol_home/.config/systemd/user/xfce4-clipman.service"
  printf 'retired gammastep service\n' >"$qol_home/.config/systemd/user/gammastep.service"
  : >"$systemctl_calls"

  (
    command() {
      if [[ "$1" == -v &&
        ("$2" == xfce4-clipman || "$2" == gammastep || "$2" == systemctl) ]]; then
        return 0
      fi
      builtin command "$@"
    }
    dev_server_home() { printf '%s\n' "$qol_home"; }
    dotfiles_xfce_brightness_floor_value() { return 1; }
    dotfiles_xfconf_set() { :; }
    dotfiles_xfwm_shortcut_set() { :; }
    dotfiles_configure_xfce_idle_policy() { :; }
    busctl() { fail 'XFCE convergence inspected session runtime ownership'; }
    systemd-run() { fail 'XFCE convergence launched a GUI process through the headless user manager'; }
    systemctl() {
      printf '%s\n' "$*" >>"$systemctl_calls"
      return 0
    }

    dotfiles_configure_xfce_qol
  ) || fail 'XFCE session-app convergence failed'

  printf '%s\n' \
    '--user disable --now xfce4-clipman.service' \
    '--user disable --now gammastep.service' \
    '--user daemon-reload' \
    '--user reset-failed xfce4-clipman.service' \
    '--user reset-failed gammastep.service' >"$expected_systemctl"
  cmp -s "$expected_systemctl" "$systemctl_calls" ||
    fail 'XFCE convergence did not retire the two headless GUI services exactly'
  [[ ! -e "$qol_home/.config/systemd/user/xfce4-clipman.service" ]] ||
    fail 'XFCE convergence retained the retired Clipman user service'
  [[ ! -e "$qol_home/.config/systemd/user/gammastep.service" ]] ||
    fail 'XFCE convergence retained the retired Gammastep user service'
  cmp -s "$repo_dir/assets/dotfiles/xfce4-clipman-autostart.desktop" \
    "$qol_home/.config/autostart/xfce4-clipman-plugin-autostart.desktop" ||
    fail 'XFCE convergence did not install the exact Clipman autostart'
  cmp -s "$repo_dir/assets/dotfiles/gammastep-autostart.desktop" \
    "$qol_home/.config/autostart/gammastep.desktop" ||
    fail 'XFCE convergence did not install the exact Gammastep autostart'
  cmp -s "$repo_dir/assets/dotfiles/gammastep.config" \
    "$qol_home/.config/gammastep/config.ini" ||
    fail 'XFCE convergence did not install the exact Gammastep configuration'
  grep -Fqx 'Exec=/usr/bin/gammastep' \
    "$repo_dir/assets/dotfiles/gammastep-autostart.desktop" ||
    fail 'Gammastep is not owned directly by the graphical XFCE session'
  [[ ! -e "$repo_dir/assets/systemd-user/gammastep.service" ]] ||
    fail 'the retired headless Gammastep service remains in the asset catalogue'
  pass
}

test_xfce_session_app_doctor() {
  local qol_home="$fixture/xfce-qol-doctor-home"
  local gammastep_active="$fixture/gammastep-active"

  install -d -m 0755 \
    "$qol_home/.config/autostart" \
    "$qol_home/.config/gammastep" \
    "$qol_home/.config/systemd/user"
  install -m 0644 "$repo_dir/assets/dotfiles/xfce4-clipman-autostart.desktop" \
    "$qol_home/.config/autostart/xfce4-clipman-plugin-autostart.desktop"
  install -m 0644 "$repo_dir/assets/dotfiles/gammastep-autostart.desktop" \
    "$qol_home/.config/autostart/gammastep.desktop"
  install -m 0644 "$repo_dir/assets/dotfiles/gammastep.config" \
    "$qol_home/.config/gammastep/config.ini"
  state_put xfce4-keyboard-shortcuts '/commands/custom/<Super>v' string \
    /usr/bin/xfce4-clipman-history
  state_put xfce4-panel /plugins/clipman/settings/max-texts-in-history uint 50

  (
    dev_server_home() { printf '%s\n' "$qol_home"; }
    dotfiles_gammastep_runtime_active() { [[ -s "$gammastep_active" ]]; }

    printf '%s\n' org.xfce.SessionManager org.xfce.clipman >"$bus_names_file"
    printf 'active\n' >"$gammastep_active"
    doctor_reset
    {
      dotfiles_doctor_xfce_clipboard_history
      dotfiles_doctor_xfce_night_color
    } >"$doctor_output"
    assert_eq 0 "$doctor_failures" 'healthy XFCE session-app doctor failure count'
    assert_eq 0 "$doctor_warnings" 'healthy XFCE session-app doctor warning count'
    assert_contains "$doctor_output" 'pass  dotfiles.clipboard-history'
    assert_contains "$doctor_output" 'pass  dotfiles.night-color'

    : >"$bus_names_file"
    : >"$gammastep_active"
    doctor_reset
    {
      dotfiles_doctor_xfce_clipboard_history
      dotfiles_doctor_xfce_night_color
    } >"$doctor_output"
    assert_eq 0 "$doctor_failures" 'headless XFCE session-app doctor failure count'
    assert_eq 2 "$doctor_warnings" 'headless XFCE session-app doctor warning count'
    assert_contains "$doctor_output" 'warn  dotfiles.clipboard-history'
    assert_contains "$doctor_output" 'warn  dotfiles.night-color'

    printf '%s\n' org.xfce.SessionManager >"$bus_names_file"
    doctor_reset
    {
      dotfiles_doctor_xfce_clipboard_history
      dotfiles_doctor_xfce_night_color
    } >"$doctor_output"
    assert_eq 2 "$doctor_failures" 'active broken XFCE session-app doctor failure count'
    assert_eq 0 "$doctor_warnings" 'active broken XFCE session-app doctor warning count'
    assert_contains "$doctor_output" 'fail  dotfiles.clipboard-history'
    assert_contains "$doctor_output" 'fail  dotfiles.night-color'

    : >"$bus_names_file"
    printf '# drift\n' >>"$qol_home/.config/autostart/gammastep.desktop"
    doctor_reset
    dotfiles_doctor_xfce_night_color >"$doctor_output"
    assert_eq 1 "$doctor_failures" 'headless Gammastep configuration drift failure count'
    assert_eq 0 "$doctor_warnings" 'headless Gammastep configuration drift warning count'
    assert_contains "$doctor_output" 'fail  dotfiles.night-color'
  ) || fail 'XFCE session-app doctor policy failed'
  pass
}

test_headless_ghostty_default() {
  local ghostty_home="$fixture/ghostty-home"
  local helpers_file="$ghostty_home/.config/xfce4/helpers.rc"
  local stable_helpers="$fixture/stable-helpers.rc"
  local systemctl_calls="$fixture/ghostty-systemctl-calls"

  install -d -m 0755 \
    "$ghostty_home/.config/xfce4" \
    "$ghostty_home/.local/share/xfce4/helpers"
  : >"$systemctl_calls"
  printf '%s\n' \
    'WebBrowser=firefox' \
    '[Helpers]' \
    'MailReader=thunderbird' \
    'TerminalEmulator=xfce4-terminal' \
    '[Other] # still a section to XFCE' \
    'FileManager=thunar' \
    '[]' \
    'TerminalEmulator=preserve-me' >"$helpers_file"

  (
    command() {
      if [[ "$1" == -v && "$2" == ghostty ]]; then
        return 0
      fi
      builtin command "$@"
    }
    uname() { printf 'Linux\n'; }
    systemctl() {
      [[ "$#" == 3 && "$1" == --user && "$2" == disable &&
        "$3" == app-com.mitchellh.ghostty.service ]] ||
        fail 'Ghostty convergence used the wrong systemctl argument vector'
      printf 'called\n' >>"$systemctl_calls"
    }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_configure_ghostty
  ) || fail 'Ghostty convergence did not repair the XFCE preferred-terminal file'

  assert_eq 1 "$(wc -l <"$systemctl_calls" | tr -d ' ')" \
    'Ghostty convergence did not remove exactly one stale service enablement'
  cmp -s "$repo_dir/assets/dotfiles/ghostty-autostart.desktop" \
    "$ghostty_home/.config/autostart/ghostty.desktop" ||
    fail 'Ghostty convergence did not install the exact XFCE service autostart'

  grep -Fqx 'TerminalEmulator=ghostty' "$helpers_file" ||
    fail 'Ghostty convergence did not write XFCE native root-level syntax'
  grep -Fqx 'WebBrowser=firefox' "$helpers_file" ||
    fail 'Ghostty convergence discarded an unrelated XFCE helper preference'
  grep -Fqx 'MailReader=thunderbird' "$helpers_file" ||
    fail 'Ghostty convergence discarded a helper preference from the legacy section'
  grep -Fqx 'FileManager=thunar' "$helpers_file" ||
    fail 'Ghostty convergence discarded a helper preference from another invalid section'
  [[ "$(grep -Ec '^[[:space:]]*TerminalEmulator[[:space:]]*=' "$helpers_file")" == 1 ]] ||
    fail 'Ghostty convergence did not normalize exactly one preferred terminal'
  ! grep -Eq '^[[:space:]]*\[.*\]' "$helpers_file" ||
    fail 'Ghostty convergence retained a section that changes XFCE lookup scope'

  cp "$helpers_file" "$stable_helpers"
  : >"$systemctl_calls"
  (
    command() {
      if [[ "$1" == -v && "$2" == ghostty ]]; then
        return 0
      fi
      builtin command "$@"
    }
    uname() { printf 'Linux\n'; }
    systemctl() {
      [[ "$#" == 3 && "$1" == --user && "$2" == disable &&
        "$3" == app-com.mitchellh.ghostty.service ]] ||
        fail 'repeat Ghostty convergence used the wrong systemctl argument vector'
      printf 'called\n' >>"$systemctl_calls"
    }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_configure_ghostty
  ) || fail 'repeat Ghostty convergence failed'
  assert_eq 1 "$(wc -l <"$systemctl_calls" | tr -d ' ')" \
    'repeat Ghostty convergence did not keep legacy enablement disabled'
  cmp -s "$stable_helpers" "$helpers_file" ||
    fail 'repeat Ghostty convergence rewrote stable XFCE helper state'

  if (
    printf() {
      [[ "$1" == 'TerminalEmulator=ghostty\n' ]] && return 1
      builtin printf "$@"
    }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_configure_xfce_ghostty_default
  ); then
    fail 'Ghostty convergence masked a failed canonical preference write'
  fi
  cmp -s "$stable_helpers" "$helpers_file" ||
    fail 'failed Ghostty convergence replaced the last-known-good helper state'

  (
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    xfce4-mime-helper() { fail 'headless Ghostty default check invoked the display-dependent helper'; }
    dotfiles_xfce_ghostty_default_configured
  ) || fail 'persisted Ghostty default did not validate without a display'

  printf '%s\n' 'TerminalEmulator=ghostty' '[Other]' 'FileManager=thunar' >"$helpers_file"
  if (
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_xfce_ghostty_default_configured
  ); then
    fail 'sectioned XFCE helper state passed the flat-file doctor boundary'
  fi

  printf '%s\n' 'TerminalEmulator=ghostty' '[]' >"$helpers_file"
  if (
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_xfce_ghostty_default_configured
  ); then
    fail 'empty XFCE helper section passed the flat-file doctor boundary'
  fi

  printf 'TerminalEmulator=xfce4-terminal\n' >"$helpers_file"
  if (
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_xfce_ghostty_default_configured
  ); then
    fail 'drifted Ghostty default passed the doctor boundary'
  fi

  printf '%s\n' '[Helpers]' 'TerminalEmulator=ghostty' >"$helpers_file"
  if (
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_xfce_ghostty_default_configured
  ); then
    fail 'legacy Git-style Ghostty section passed the XFCE-native doctor boundary'
  fi

  printf 'TerminalEmulator=ghostty\n' >"$helpers_file"
  printf '# drift\n' >>"$ghostty_home/.local/share/xfce4/helpers/ghostty.desktop"
  if (
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_xfce_ghostty_default_configured
  ); then
    fail 'drifted Ghostty helper definition passed the doctor boundary'
  fi
  pass
}

test_ghostty_xfce_autostart() {
  local ghostty_home="$fixture/ghostty-home"
  local autostart="$ghostty_home/.config/autostart/ghostty.desktop"

  (
    systemctl() {
      [[ "$#" == 3 && "$1" == --user && "$2" == is-enabled &&
        "$3" == app-com.mitchellh.ghostty.service ]] ||
        fail 'Ghostty service doctor used the wrong systemctl argument vector'
      printf 'disabled\n'
    }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_ghostty_service_configured
  ) || fail 'Ghostty service doctor rejected exact XFCE autostart state'

  if (
    systemctl() { printf 'enabled\n'; }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_ghostty_service_configured
  ); then
    fail 'Ghostty service doctor accepted stale systemd enablement'
  fi

  printf '# drift\n' >>"$autostart"
  if (
    systemctl() { printf 'disabled\n'; }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_ghostty_service_configured
  ); then
    fail 'Ghostty service doctor accepted a drifted XFCE autostart'
  fi
  install -m 0644 "$repo_dir/assets/dotfiles/ghostty-autostart.desktop" "$autostart"
  pass
}

test_ghostty_non_xfce_convergence() {
  local ghostty_home="$fixture/non-xfce-ghostty-home"
  local systemctl_calls="$fixture/non-xfce-ghostty-systemctl-calls"

  : >"$systemctl_calls"
  (
    platform_id() { printf 'devbox\n'; }
    command() {
      if [[ "$1" == -v && "$2" == ghostty ]]; then
        return 0
      fi
      builtin command "$@"
    }
    uname() { printf 'Linux\n'; }
    systemctl() {
      [[ "$#" == 4 && "$1" == --user && "$2" == enable && "$3" == --now &&
        "$4" == app-com.mitchellh.ghostty.service ]] ||
        fail 'non-XFCE Ghostty convergence used the wrong systemctl argument vector'
      printf 'called\n' >>"$systemctl_calls"
    }
    dev_server_home() { printf '%s\n' "$ghostty_home"; }
    dotfiles_configure_ghostty
  ) || fail 'non-XFCE Ghostty convergence failed'

  assert_eq 1 "$(wc -l <"$systemctl_calls" | tr -d ' ')" \
    'non-XFCE Ghostty convergence did not start the user service exactly once'
  [[ ! -e "$ghostty_home/.config/autostart/ghostty.desktop" ]] ||
    fail 'non-XFCE Ghostty convergence installed an XFCE-only autostart'
  pass
}

test_tmux_session_title_convergence() {
  local tmux_asset="$repo_dir/assets/dotfiles/tmux.conf"
  local tmux_calls="$fixture/tmux-calls"
  local tmux_doctor_failures="$fixture/tmux-doctor-failures"
  local tmux_doctor_output="$fixture/tmux-doctor-output"
  local tmux_home="$fixture/tmux-home"

  assert_eq 1 "$(grep -Fxc -- 'set -g set-titles on' "$tmux_asset")" \
    'managed tmux config must enable terminal titles exactly once'
  assert_eq 1 "$(grep -Fxc -- "set -g set-titles-string '#{session_name}'" "$tmux_asset")" \
    'managed tmux config must use only the session name as the terminal title'

  install -d -m 0755 "$tmux_home"
  install -m 0644 "$tmux_asset" "$tmux_home/.tmux.conf"

  : >"$tmux_calls"
  (
    dev_server_home() { printf '%s\n' "$tmux_home"; }
    tmux() {
      printf '%s\n' "$*" >>"$tmux_calls"
      return 0
    }

    dotfiles_reload_tmux_if_running
  ) || fail 'active tmux server reload failed'
  assert_eq $'list-sessions\nsource-file '"$tmux_home/.tmux.conf" \
    "$(cat "$tmux_calls")" \
    'active tmux server did not reload the managed config exactly once'

  : >"$tmux_calls"
  (
    dev_server_home() { printf '%s\n' "$tmux_home"; }
    tmux() {
      printf '%s\n' "$*" >>"$tmux_calls"
      return 1
    }

    dotfiles_reload_tmux_if_running
  ) || fail 'inactive tmux server reload path failed'
  assert_eq 'list-sessions' "$(cat "$tmux_calls")" \
    'inactive tmux server path attempted to source the managed config'

  (
    doctor_reset
    dev_server_home() { printf '%s\n' "$tmux_home"; }
    dotfiles_doctor_tmux
    printf '%s\n' "$doctor_failures" >"$tmux_doctor_failures"
  ) >"$tmux_doctor_output"
  assert_eq 0 "$(cat "$tmux_doctor_failures")" 'exact managed tmux config failed its doctor'
  assert_contains "$tmux_doctor_output" 'pass  dotfiles.tmux.conf'

  printf '# drift\n' >>"$tmux_home/.tmux.conf"
  (
    doctor_reset
    dev_server_home() { printf '%s\n' "$tmux_home"; }
    dotfiles_doctor_tmux
    printf '%s\n' "$doctor_failures" >"$tmux_doctor_failures"
  ) >"$tmux_doctor_output"
  assert_eq 1 "$(cat "$tmux_doctor_failures")" 'drifted tmux config passed its doctor'
  assert_contains "$tmux_doctor_output" 'fail  dotfiles.tmux.conf'
  pass
}

test_production_wiring() {
  local configure_calls="$fixture/configure-wiring-calls"
  local doctor_calls="$fixture/doctor-wiring-calls"
  local ghostty_doctor_calls="$fixture/ghostty-doctor-wiring-calls"
  local ghostty_service_doctor_calls="$fixture/ghostty-service-doctor-wiring-calls"
  local non_xfce_doctor_output="$fixture/non-xfce-doctor-output"

  : >"$configure_calls"
  : >"$doctor_calls"
  : >"$ghostty_doctor_calls"
  : >"$ghostty_service_doctor_calls"
  (
    unset XDG_CURRENT_DESKTOP
    command() {
      if [[ "$1" == -v && "$2" == xfconf-query ]]; then
        return 0
      fi
      if [[ "$1" == -v && "$2" == systemctl ]]; then
        return 0
      fi
      if [[ "$1" == -v && ("$2" == xfce4-clipman || "$2" == gammastep) ]]; then
        return 1
      fi
      builtin command "$@"
    }
    dev_server_home() { printf '%s\n' "$fixture"; }
    dotfiles_xfce_brightness_floor_value() { return 1; }
    dotfiles_xfconf_set() { :; }
    dotfiles_xfwm_shortcut_set() { :; }
    dotfiles_configure_xfce_idle_policy() { printf 'called\n' >>"$configure_calls"; }
    systemctl() { :; }

    dotfiles_configure_xfce_qol
  )
  assert_eq 1 "$(wc -l <"$configure_calls" | tr -d ' ')" \
    'quality-of-life convergence did not call the focused idle-policy boundary exactly once'

  (
    unset XDG_CURRENT_DESKTOP
    command() {
      [[ "$1" == -v && ("$2" == xfconf-query || "$2" == ghostty) ]]
    }
    uname() { printf 'Linux\n'; }
    systemctl() { return 1; }
    dev_server_home() { printf '%s\n' "$fixture"; }
    dotfiles_xfce_brightness_floor_value() { return 1; }
    dotfiles_doctor_xfce_idle_policy() { printf 'called\n' >>"$doctor_calls"; }
    dotfiles_xfce_ghostty_default_configured() {
      printf 'called\n' >>"$ghostty_doctor_calls"
    }
    dotfiles_ghostty_service_configured() {
      printf 'called\n' >>"$ghostty_service_doctor_calls"
    }
    git() { printf 'main\n'; }

    dotfiles_doctor >/dev/null
  )
  assert_eq 1 "$(wc -l <"$doctor_calls" | tr -d ' ')" \
    'dotfiles doctor did not call the focused idle-policy boundary exactly once'
  assert_eq 1 "$(wc -l <"$ghostty_doctor_calls" | tr -d ' ')" \
    'dotfiles doctor did not call the headless Ghostty-default boundary exactly once'
  assert_eq 1 "$(wc -l <"$ghostty_service_doctor_calls" | tr -d ' ')" \
    'dotfiles doctor did not check the XFCE Ghostty autostart exactly once'

  (
    platform_id() { printf 'devbox\n'; }
    command() { [[ "$1" == -v && "$2" == ghostty ]]; }
    uname() { printf 'Linux\n'; }
    dev_server_home() { printf '%s\n' "$fixture"; }
    dotfiles_ghostty_service_configured() { return 0; }
    git() { printf 'main\n'; }

    dotfiles_doctor
  ) >"$non_xfce_doctor_output"
  assert_contains "$non_xfce_doctor_output" 'Ghostty user service enabled'
  pass
}

test_exact_idle_policy_convergence
test_idle_policy_type_repair
test_idle_policy_drift
test_idle_policy_runtime_doctor
test_declared_platform_boundary
test_declared_packages
test_xfce_session_app_convergence
test_xfce_session_app_doctor
test_headless_ghostty_default
test_ghostty_xfce_autostart
test_ghostty_non_xfce_convergence
test_tmux_session_title_convergence
test_production_wiring

printf 'PASS: %d XFCE dotfiles test groups\n' "$tests_run"
